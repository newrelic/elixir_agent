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
        {module, function, args},
        {name, category: :datastore},
        pid,
        {id, parent_id},
        {start_time, start_time_mono, end_time_mono}
      ) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    arity = length(args)

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
      timestamp_ms: start_time,
      duration_s: duration_s,
      name: function_name({module, function, arity}, name),
      category: "datastore",
      attributes: Map.put(NewRelic.DistributedTrace.get_span_attrs(), :args, inspect(args)),
      edge: [span: id, parent: parent_id]
    )

    NewRelic.incr_attributes(
      timestamp_ms: System.convert_time_unit(start_time, :native, :milliseconds),
      datastore_call_count: 1,
      datastore_duration_ms: duration_ms,
      "datastore.#{function_name({module, function}, name)}.call_count": 1,
      "datastore.#{function_name({module, function}, name)}.duration_ms": duration_ms
    )

    NewRelic.report_aggregate(
      %{
        name: :FunctionTrace,
        mfa: function_name({module, function, arity}, name),
        metric_category: :datastore
      },
      %{duration_ms: duration_ms, call_count: 1}
    )

    NewRelic.report_metric(
      {:datastore, "/#{function_name({module, function}, name)}"},
      duration_s: duration_s
    )
  end

  def call(
        {module, function, args},
        {name, category: :external},
        pid,
        {id, parent_id},
        {start_time, start_time_mono, end_time_mono}
      ) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    arity = length(args)

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
      timestamp_ms: System.convert_time_unit(start_time, :native, :milliseconds),
      duration_s: duration_s,
      name: function_name({module, function, arity}, name),
      category: "http",
      attributes: Map.put(NewRelic.DistributedTrace.get_span_attrs(), :args, inspect(args)),
      edge: [span: id, parent: parent_id]
    )

    NewRelic.incr_attributes(
      external_call_count: 1,
      external_duration_ms: duration_ms,
      "external.#{function_name({module, function}, name)}.call_count": 1,
      "external.#{function_name({module, function}, name)}.duration_ms": duration_ms
    )

    NewRelic.report_aggregate(
      %{
        name: :FunctionTrace,
        mfa: function_name({module, function, arity}, name),
        metric_category: :external
      },
      %{duration_ms: duration_ms, call_count: 1}
    )

    NewRelic.report_metric(
      {:external, "/#{function_name({module, function}, name)}"},
      duration_s: duration_s
    )
  end

  def call(
        {module, function, args},
        name,
        pid,
        {id, parent_id},
        {start_time, start_time_mono, end_time_mono}
      )
      when is_atom(name) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    arity = length(args)

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
      timestamp_ms: System.convert_time_unit(start_time, :native, :milliseconds),
      duration_s: duration_s,
      name: function_name({module, function, arity}, name),
      category: "generic",
      attributes: Map.put(NewRelic.DistributedTrace.get_span_attrs(), :args, inspect(args)),
      edge: [span: id, parent: parent_id]
    )

    NewRelic.report_aggregate(
      %{name: :FunctionTrace, mfa: function_name({module, function, arity}, name)},
      %{duration_ms: duration_ms, call_count: 1}
    )
  end

  def duration_ms(start_time_mono, end_time_mono),
    do: System.convert_time_unit(end_time_mono - start_time_mono, :native, :milliseconds)

  defp function_name({m, f}, f), do: "#{inspect(m)}.#{f}"
  defp function_name({m, f}, i), do: "#{inspect(m)}.#{f}:#{i}"
  defp function_name({m, f, a}, f), do: "#{inspect(m)}.#{f}/#{a}"
  defp function_name({m, f, a}, i), do: "#{inspect(m)}.#{f}:#{i}/#{a}"
end
