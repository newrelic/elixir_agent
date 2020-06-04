defmodule NewRelic.Transaction.Reporter do
  use GenServer

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
    Transaction.Store.add(
      attrs
      |> NewRelic.Util.deep_flatten()
      |> NewRelic.Util.coerce_attributes()
    )
  end

  def incr_attributes(attrs) do
    Transaction.Store.incr(attrs)
  end

  def set_transaction_name(custom_name) when is_binary(custom_name) do
    Transaction.Store.add(custom_name: custom_name)
  end

  # Internal Agent API

  def start() do
    Transaction.Monitor.add(self())

    Transaction.Store.track()
    Transaction.Store.add(pid: inspect(self()))
  end

  def start_other_transaction(category, name) do
    unless Transaction.Store.tracking?() do
      start()

      Transaction.Store.add(
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
    Transaction.Store.ignore()
  end

  def error(pid, error) do
    Transaction.Store.add(transaction_error: {:error, error})
  end

  def fail(%{kind: kind, reason: reason, stack: stack} = error) do
    if NewRelic.Config.feature?(:error_collector) do
      Transaction.Store.add(
        error: true,
        error_kind: kind,
        error_reason: inspect(reason),
        error_stack: inspect(stack)
      )
    else
      Transaction.Store.add(error: true)
    end
  end

  def add_trace_segment(segment) do
    Transaction.Store.add(trace_function_segments: {:list, segment})
  end

  def track_metric(metric) do
    Transaction.Store.add(transaction_metrics: {:list, metric})
  end

  def complete(pid, mode) do
    Transaction.Store.add(end_time_mono: System.monotonic_time())

    case mode do
      :sync ->
        Transaction.Store.complete()

      :async ->
        :nothin
    end
  end

  # Internal Transaction.Monitor API
  #

  def track_spawn(original, pid, timestamp) do
    Transaction.Store.connect(original, pid)

    Transaction.Store.add(original,
      trace_process_spawns: {:list, {pid, timestamp, original}},
      trace_process_names: {:list, {pid, NewRelic.Util.process_name(pid)}}
    )
  end

  def track_exit(pid, timestamp) do
    Transaction.Store.add(pid, trace_process_exits: {:list, {pid, timestamp}})
  end

  # GenServer
  #

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    {:ok, %{timers: %{}}}
  end
end
