defmodule NewRelic.Transaction.Reporter do
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
    Transaction.Sidecar.add(
      attrs
      |> NewRelic.Util.deep_flatten()
      |> NewRelic.Util.coerce_attributes()
    )
  end

  def incr_attributes(attrs) do
    Transaction.Sidecar.incr(attrs)
  end

  def set_transaction_name(custom_name) when is_binary(custom_name) do
    Transaction.Sidecar.add(custom_name: custom_name)
  end

  # Internal Agent API

  def start() do
    Transaction.Monitor.add()
    Transaction.Sidecar.track()
  end

  def start_other_transaction() do
    unless Transaction.Sidecar.tracking?() do
      start()
    end
  end

  def stop_other_transaction() do
    Transaction.Sidecar.add(end_time_mono: System.monotonic_time())
    Transaction.Sidecar.complete()
  end

  def ignore_transaction() do
    Transaction.Sidecar.ignore()
  end

  def error(pid, error) do
    Transaction.Store.add(transaction_error: {:error, error})
  end

  def fail(%{kind: kind, reason: reason, stack: stack} = error) do
    if NewRelic.Config.feature?(:error_collector) do
      Transaction.Sidecar.add(
        error: true,
        error_kind: kind,
        error_reason: inspect(reason),
        error_stack: inspect(stack)
      )
    else
      Transaction.Sidecar.add(error: true)
    end
  end

  def add_trace_segment(segment) do
    Transaction.Sidecar.add(trace_function_segments: {:list, segment})
  end

  def track_metric(metric) do
    Transaction.Sidecar.add(transaction_metrics: {:list, metric})
  end

  # Internal Transaction.Monitor API
  #

  def track_spawn(original, pid, timestamp) do
    Transaction.Sidecar.connect(original, pid)

    Transaction.Sidecar.add(original,
      trace_process_spawns: {:list, {pid, timestamp, original}},
      trace_process_names: {:list, {pid, NewRelic.Util.process_name(pid)}}
    )
  end

  def track_exit(pid, timestamp) do
    # Problem
    # when using in process storage, we don't know where to send the exit
    # since the process is gone

    # could: use DOWN messages to mark exit
    Transaction.Sidecar.add(pid, trace_process_exits: {:list, {pid, timestamp}})
  end
end
