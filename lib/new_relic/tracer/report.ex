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
        mfa,
        trace_annotation,
        pid,
        edge,
        timing
      ) do
    {name, options} =
      case trace_annotation do
        {name, options} -> {name, options}
        name -> {name, []}
      end

    category = Keyword.get(options, :category, :function)

    report(
      category,
      options,
      mfa,
      name,
      pid,
      edge,
      timing
    )
  end

  defp report(
         :external,
         options,
         {module, function, arguments},
         name,
         pid,
         {id, parent_id},
         {start_time, start_time_mono, end_time_mono, _child_duration_ms}
       ) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    span_attrs = NewRelic.DistributedTrace.get_span_attrs()

    case span_attrs do
      %{url: url, component: component, method: method} ->
        %{host: host} = URI.parse(url)

        metric_name = "External/#{host}/#{component}/#{method}"
        secondary_name = "#{host} - #{component}/#{method}"

        Transaction.Reporter.add_trace_segment(%{
          primary_name: metric_name,
          secondary_name: secondary_name,
          attributes: %{},
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
          name: metric_name,
          edge: [span: id, parent: parent_id],
          category: "http",
          attributes: span_attrs
        )

        NewRelic.report_metric({:external, url, component, method}, duration_s: duration_s)

        Transaction.Reporter.track_metric({
          {:external, url, component, method},
          duration_s: duration_s
        })

      _ ->
        arity = length(arguments)
        args = inspect_args(arguments, Keyword.take(options, [:args]))

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

        NewRelic.report_metric({:external, function_name}, duration_s: duration_s)

        Transaction.Reporter.track_metric({
          {:external, function_name},
          duration_s: duration_s
        })
    end

    NewRelic.incr_attributes(
      externalCallCount: 1,
      externalDuration: duration_s,
      external_call_count: 1,
      external_duration_ms: duration_ms
    )

    Transaction.Reporter.track_metric({:external, duration_s})
  end

  defp report(
         :function,
         options,
         {module, function, arguments},
         name,
         pid,
         {id, parent_id},
         {start_time, start_time_mono, end_time_mono, child_duration_ms}
       ) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    exclusive_time_s = duration_s - child_duration_ms / 1000

    arity = length(arguments)
    args = inspect_args(arguments, Keyword.take(options, [:args]))
    function_name = function_name({module, function, arity}, name)

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
      name: function_name,
      edge: [span: id, parent: parent_id],
      category: "generic",
      attributes: Map.put(NewRelic.DistributedTrace.get_span_attrs(), :args, args)
    )

    NewRelic.report_aggregate(
      %{name: :FunctionTrace, mfa: function_name},
      %{duration_ms: duration_ms, call_count: 1}
    )

    NewRelic.report_metric(
      {:function, function_name},
      duration_s: duration_s,
      exclusive_time_s: exclusive_time_s
    )

    Transaction.Reporter.track_metric({
      {:function, function_name},
      duration_s: duration_s, exclusive_time_s: exclusive_time_s
    })
  end

  defp inspect_args(_arguments, args: false) do
    "[DISABLED]"
  end

  defp inspect_args(arguments, _) do
    if NewRelic.Config.feature?(:function_argument_collection) do
      inspect(arguments, charlists: :as_lists, limit: 5, printable_limit: 10)
    else
      "[DISABLED]"
    end
  end

  defp duration_ms(start_time_mono, end_time_mono),
    do: System.convert_time_unit(end_time_mono - start_time_mono, :native, :millisecond)

  defp function_name({m, f}, f), do: "#{inspect(m)}.#{f}"
  defp function_name({m, f}, i), do: "#{inspect(m)}.#{f}:#{i}"
  defp function_name({m, f, a}, f), do: "#{inspect(m)}.#{f}/#{a}"
  defp function_name({m, f, a}, i), do: "#{inspect(m)}.#{f}:#{i}/#{a}"
end
