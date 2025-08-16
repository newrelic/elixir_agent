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

  def add_attributes(attrs) when is_list(attrs) do
    attrs
    |> NewRelic.Util.deep_flatten()
    |> NewRelic.Util.coerce_attributes()
    |> Transaction.Sidecar.add()
  end

  def incr_attributes(attrs) do
    Transaction.Sidecar.incr(attrs)
  end

  def set_transaction_name(custom_name) when is_binary(custom_name) do
    Transaction.Sidecar.add(custom_name: custom_name)
  end

  def start_transaction(:web, path) do
    unless Transaction.Sidecar.tracking?() do
      {system_time, start_time_mono} = {System.system_time(), System.monotonic_time()}

      if NewRelic.Util.path_match?(path, NewRelic.Config.ignore_paths()) do
        ignore_transaction()
        :ignore
      else
        Transaction.ErlangTrace.trace()
        Transaction.Sidecar.track(:web)
        Transaction.Sidecar.add(system_time: system_time, start_time_mono: start_time_mono)
        :collect
      end
    end
  end

  def start_transaction(:other) do
    {system_time, start_time_mono} = {System.system_time(), System.monotonic_time()}

    unless Transaction.Sidecar.tracking?() do
      Transaction.ErlangTrace.trace()
      Transaction.Sidecar.track(:other)
      Transaction.Sidecar.add(system_time: system_time, start_time_mono: start_time_mono)
    end
  end

  def stop_transaction(:web) do
    Transaction.Sidecar.add(end_time_mono: System.monotonic_time())
    Transaction.Sidecar.complete()
  end

  def stop_transaction(:other) do
    Transaction.Sidecar.add(end_time_mono: System.monotonic_time())
    Transaction.Sidecar.complete()
  end

  def ignore_transaction() do
    Transaction.Sidecar.ignore()
    :ok
  end

  def exclude_from_transaction() do
    Transaction.Sidecar.exclude()
    :ok
  end

  def get_transaction() do
    %{
      sidecar: Transaction.Sidecar.get_sidecar(),
      parent:
        case NewRelic.DistributedTrace.read_current_span() do
          nil -> self()
          {label, ref} -> {self(), label, ref}
        end
    }
  end

  def connect_to_transaction(tx_ref) do
    Transaction.Sidecar.connect(tx_ref)
    :ok
  end

  def disconnect_from_transaction() do
    Transaction.Sidecar.disconnect()
    :ok
  end

  def notice_error(exception, stacktrace) do
    if NewRelic.Config.feature?(:error_collector) do
      error(%{kind: :error, reason: exception, stack: stacktrace})
    end

    :ok
  end

  def error(%{kind: kind, reason: reason, stack: stack} = error) do
    Process.put(:nr_error_explicitly_reported, {kind, reason, List.first(stack)})
    Transaction.Sidecar.add(error: true, transaction_error: {:error, error})
  end

  def add_trace_segment(segment) do
    Transaction.Sidecar.append(function_segments: segment)
  end

  def track_metric(metric) do
    Transaction.Sidecar.append(transaction_metrics: metric)
  end

  def track_spawn(parent, child, timestamp) do
    Transaction.Sidecar.track_spawn(parent, child, timestamp)
  end
end
