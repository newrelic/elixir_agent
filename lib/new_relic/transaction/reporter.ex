defmodule NewRelic.Transaction.Reporter do
  use GenServer

  alias NewRelic.Util.AttrStore
  alias NewRelic.Transaction

  # This GenServer collects and reports Transaction related data
  #  - Transaction Events
  #  - Transaction Metrics
  #  - Span Events
  #  - Transaction Errors
  #  - Transaction Traces
  #  - Custom Attributes

  @moduledoc false

  # Customer Exposed API

  def add_attributes(attrs) when is_list(attrs) do
    if tracking?(self()) do
      Transaction.Store.add(
        attrs
        |> NewRelic.Util.deep_flatten()
        |> NewRelic.Util.coerce_attributes()
      )

      AttrStore.add(
        __MODULE__,
        self(),
        attrs
        |> NewRelic.Util.deep_flatten()
        |> NewRelic.Util.coerce_attributes()
      )
    end
  end

  def incr_attributes(attrs) do
    if tracking?(self()) do
      Transaction.Store.incr(attrs)

      AttrStore.incr(__MODULE__, self(), attrs)
    end
  end

  def set_transaction_name(custom_name) when is_binary(custom_name) do
    if tracking?(self()) do
      Transaction.Store.add(custom_name: custom_name)

      AttrStore.add(__MODULE__, self(), custom_name: custom_name)
    end
  end

  # Internal Agent API

  def start() do
    Transaction.Monitor.add(self())

    Transaction.Store.track()
    Transaction.Store.add(pid: inspect(self()))

    AttrStore.track(__MODULE__, self())
    AttrStore.add(__MODULE__, self(), pid: inspect(self()))
  end

  def start_other_transaction(category, name) do
    unless tracking?(self()) do
      start()

      Transaction.Store.add(
        start_time: System.system_time(),
        start_time_mono: System.monotonic_time(),
        other_transaction_name: "#{category}/#{name}"
      )

      AttrStore.add(__MODULE__, self(),
        start_time: System.system_time(),
        start_time_mono: System.monotonic_time(),
        other_transaction_name: "#{category}/#{name}"
      )
    end
  end

  def stop_other_transaction() do
    complete(self(), :sync)
  end

  def ignore_transaction() do
    if tracking?(self()) do
      Transaction.Store.ignore()

      ensure_purge(self())
      AttrStore.untrack(__MODULE__, self())
      AttrStore.purge(__MODULE__, self())
    end
  end

  def error(pid, error) do
    if tracking?(pid) do
      AttrStore.add(__MODULE__, pid, transaction_error: {:error, error})
    end
  end

  def fail(pid, %{kind: kind, reason: reason, stack: stack} = error) do
    if tracking?(pid) do
      if NewRelic.Config.feature?(:error_collector) do
        Transaction.Store.add(
          error: true,
          transaction_error: {:error, error},
          error_kind: kind,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        )

        AttrStore.add(__MODULE__, pid,
          error: true,
          error_kind: kind,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        )
      else
        Transaction.Store.add(error: true)

        AttrStore.add(__MODULE__, pid, error: true)
      end
    end
  end

  def add_trace_segment(segment) do
    if tracking?(self()) do
      Transaction.Store.add(trace_function_segments: {:list, segment})

      AttrStore.add(__MODULE__, self(), trace_function_segments: {:list, segment})
    end
  end

  def track_metric(metric) do
    if tracking?(self()) do
      Transaction.Store.add(transaction_metrics: {:list, metric})

      AttrStore.add(__MODULE__, self(), transaction_metrics: {:list, metric})
    end
  end

  def complete(pid, mode) do
    if tracking?(pid) do
      Transaction.Store.add(end_time_mono: System.monotonic_time())

      AttrStore.untrack(__MODULE__, pid)
      AttrStore.add(__MODULE__, pid, end_time_mono: System.monotonic_time())

      case mode do
        :sync ->
          Transaction.Store.complete()

        :async ->
          Task.Supervisor.start_child(Transaction.TaskSupervisor, fn ->
            complete_and_purge(pid)
          end)
      end
    end
  end

  defp complete_and_purge(pid) do
    # AttrStore.collect(__MODULE__, pid)
    # |> Transaction.Complete.run(pid)

    AttrStore.purge(__MODULE__, pid)
  end

  # Internal Transaction.Monitor API
  #

  def track_spawn(original, pid, timestamp) do
    if tracking?(original) do
      Transaction.Store.link(original, pid)

      Transaction.Store.add(original,
        trace_process_spawns: {:list, {pid, timestamp, original}},
        trace_process_names: {:list, {pid, NewRelic.Util.process_name(pid)}}
      )

      AttrStore.link(__MODULE__, original, pid)

      AttrStore.add(__MODULE__, pid,
        trace_process_spawns: {:list, {pid, timestamp, original}},
        trace_process_names: {:list, {pid, NewRelic.Util.process_name(pid)}}
      )
    end
  end

  def track_exit(pid, timestamp) do
    if tracking?(pid) do
      Transaction.Store.add(pid, trace_process_exits: {:list, {pid, timestamp}})

      AttrStore.add(__MODULE__, pid, trace_process_exits: {:list, {pid, timestamp}})
    end
  end

  # Try really hard not to leak memory if any async reporting trickles in late
  def ensure_purge(pid) do
    Process.send_after(
      __MODULE__,
      {:ensure_purge, AttrStore.root(__MODULE__, pid)},
      Application.get_env(:new_relic_agent, :ensure_purge_after, 2_000)
    )
  end

  # GenServer
  #

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    AttrStore.new(__MODULE__)
    {:ok, %{timers: %{}}}
  end

  def handle_info({:ensure_purge, pid}, state) do
    AttrStore.purge(__MODULE__, pid)
    {:noreply, %{state | timers: Map.drop(state.timers, [pid])}}
  end

  # Helpers
  #

  def tracking?(pid), do: AttrStore.tracking?(__MODULE__, pid)

  def root(pid), do: AttrStore.root(__MODULE__, pid)
end
