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
      AttrStore.add(__MODULE__, self(), NewRelic.Util.deep_flatten(attrs))
    end
  end

  def incr_attributes(attrs) do
    if tracking?(self()) do
      AttrStore.incr(__MODULE__, self(), attrs)
    end
  end

  def set_transaction_name(custom_name) do
    if tracking?(self()) do
      AttrStore.add(__MODULE__, self(), custom_name: custom_name)
    end
  end

  # Internal Agent API
  #

  def start() do
    Transaction.Monitor.add(self())
    AttrStore.track(__MODULE__, self())

    add_attributes(
      pid: inspect(self()),
      start_time: System.system_time(),
      start_time_mono: System.monotonic_time()
    )
  end

  def start_other_transaction(category, name) do
    unless tracking?(self()) do
      start()
      AttrStore.add(__MODULE__, self(), other_transaction_name: "#{category}/#{name}")
    end
  end

  def ignore_transaction() do
    if tracking?(self()) do
      AttrStore.untrack(__MODULE__, self())
      AttrStore.purge(__MODULE__, self())
      ensure_purge(self())
    end
  end

  def fail(%{kind: kind, reason: reason, stack: stack} = error) do
    if tracking?(self()) do
      if NewRelic.Config.feature?(:error_collector) do
        add_attributes(
          error: true,
          transaction_error: {:error, error},
          error_kind: kind,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        )
      else
        add_attributes(error: true)
      end
    end
  end

  def add_trace_segment(segment) do
    if tracking?(self()) do
      AttrStore.add(__MODULE__, self(), trace_function_segments: {:list, segment})
    end
  end

  def track_metric(metric) do
    if tracking?(self()) do
      AttrStore.add(__MODULE__, self(), transaction_metrics: {:list, metric})
    end
  end

  def set_transaction_error(pid, error) do
    if tracking?(pid) do
      AttrStore.add(__MODULE__, pid, transaction_error: {:error, error})
    end
  end

  def complete(pid \\ self()) do
    if tracking?(pid) do
      AttrStore.add(__MODULE__, pid, end_time_mono: System.monotonic_time())
      AttrStore.untrack(__MODULE__, pid)

      Task.Supervisor.start_child(NewRelic.Transaction.TaskSupervisor, fn ->
        AttrStore.collect(__MODULE__, pid)
        |> Transaction.Complete.run(pid)
      end)
    end
  end

  # Internal Transaction.Monitor API
  #

  def track_spawn(original, pid, timestamp) do
    if tracking?(original) do
      AttrStore.link(
        __MODULE__,
        original,
        pid,
        trace_process_spawns: {:list, {pid, timestamp, original}},
        trace_process_names: {:list, {pid, NewRelic.Util.process_name(pid)}}
      )

      AttrStore.incr(__MODULE__, original, process_spawns: 1)
    end
  end

  def track_exit(pid, timestamp) do
    if tracking?(pid) do
      AttrStore.add(__MODULE__, pid, trace_process_exits: {:list, {pid, timestamp}})
    end
  end

  def ensure_purge(pid) do
    Process.send_after(
      __MODULE__,
      {:purge, AttrStore.find_root(__MODULE__, pid)},
      Application.get_env(:new_relic_agent, :tx_pid_expire, 2_000)
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

  def handle_info({:purge, pid}, state) do
    AttrStore.purge(__MODULE__, pid)
    {:noreply, %{state | timers: Map.drop(state.timers, [pid])}}
  end

  # Helpers
  #

  def tracking?(pid), do: AttrStore.tracking?(__MODULE__, pid)

  def root(pid), do: AttrStore.find_root(__MODULE__, pid)
end
