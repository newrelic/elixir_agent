defmodule NewRelic.Tracer.Report do
  alias NewRelic.Transaction

  # Helper functions that will report traced function events in their various forms
  #  - Transaction Trace segments
  #  - Distributed Trace spans
  #  - Transaction attributes
  #  - Metrics
  #  - Aggregate metric-like NRDB events

  @moduledoc false

  def call(
        {module, function, arguments},
        {name, category: :external},
        pid,
        {id, parent_id},
        {start_time, start_time_mono, end_time_mono}
      ) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    arity = length(arguments)
    args = inspect_args(arguments)
    span_attrs = NewRelic.DistributedTrace.get_span_attrs()

    function_name = function_name({module, function}, name)
    function_arity_name = function_name({module, function, arity}, name)

    Transaction.Reporter.add_trace_segment(%{
      module: module,
      function: function,
      arity: arity,
      name: name,
      args: args,
      pid: pid,
      id: id,
      parent_id: parent_id,
      start_time: start_time,
      start_time_mono: start_time_mono,
      end_time_mono: end_time_mono
    })

    NewRelic.report_span(
      timestamp_ms: System.convert_time_unit(start_time, :native, :millisecond),
      duration_s: duration_s,
      name: function_arity_name,
      edge: [span: id, parent: parent_id],
      category: "http",
      attributes: Map.put(span_attrs, :args, args)
    )

    NewRelic.incr_attributes(
      external_call_count: 1,
      external_duration_ms: duration_ms,
      "external.#{function_name}.call_count": 1,
      "external.#{function_name}.duration_ms": duration_ms
    )

    NewRelic.report_aggregate(
      %{
        name: :FunctionTrace,
        mfa: function_arity_name,
        metric_category: :external
      },
      %{duration_ms: duration_ms, call_count: 1}
    )

    Transaction.Reporter.track_metric({:external, duration_s})

    case span_attrs do
      %{url: url, component: component, method: method} ->
        NewRelic.report_metric({:external, url, component, method}, duration_s: duration_s)

      _ ->
        NewRelic.report_metric({:external, function_name}, duration_s: duration_s)
    end
  end

  def call(
        {module, function, arguments},
        name,
        pid,
        {id, parent_id},
        {start_time, start_time_mono, end_time_mono}
      )
      when is_atom(name) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    arity = length(arguments)
    args = inspect_args(arguments)

    Transaction.Reporter.add_trace_segment(%{
      module: module,
      function: function,
      arity: arity,
      name: name,
      args: args,
      pid: pid,
      id: id,
      parent_id: parent_id,
      start_time: start_time,
      start_time_mono: start_time_mono,
      end_time_mono: end_time_mono
    })

    NewRelic.report_span(
      timestamp_ms: System.convert_time_unit(start_time, :native, :millisecond),
      duration_s: duration_s,
      name: function_name({module, function, arity}, name),
      edge: [span: id, parent: parent_id],
      category: "generic",
      attributes: Map.put(NewRelic.DistributedTrace.get_span_attrs(), :args, args)
    )

    NewRelic.report_aggregate(
      %{name: :FunctionTrace, mfa: function_name({module, function, arity}, name)},
      %{duration_ms: duration_ms, call_count: 1}
    )
  end

  defp inspect_args(arguments) do
    inspect(arguments, charlists: :as_lists, limit: 20, printable_limit: 100)
  end

  defp duration_ms(start_time_mono, end_time_mono),
    do: System.convert_time_unit(end_time_mono - start_time_mono, :native, :millisecond)

  defp function_name({m, f}, f), do: "#{inspect(m)}.#{f}"
  defp function_name({m, f}, i), do: "#{inspect(m)}.#{f}:#{i}"
  defp function_name({m, f, a}, f), do: "#{inspect(m)}.#{f}/#{a}"
  defp function_name({m, f, a}, i), do: "#{inspect(m)}.#{f}:#{i}/#{a}"
  defp function_name(f, f), do: "#{f}"
  defp function_name(_f, i), do: "#{i}"
end
