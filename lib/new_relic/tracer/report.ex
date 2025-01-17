defmodule NewRelic.Tracer.Report do
  alias NewRelic.Transaction

  # Helper functions that will report traced function events in their various forms
  #  - Transaction Trace segments
  #  - Distributed Trace Span events
  #  - Transaction attributes
  #  - Metrics

  @moduledoc false

  def call(
        mfa,
        trace_annotation,
        pid,
        edge,
        timing
      ) do
    {name, options} = trace_annotation
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
         {system_time, start_time_mono, end_time_mono, _child_duration_ms, reductions}
       ) do
    duration_ms = duration_ms(start_time_mono, end_time_mono)
    duration_s = duration_ms / 1000
    arity = length(arguments)
    args = inspect_args(arguments, Keyword.take(options, [:args]))
    span_attrs = NewRelic.DistributedTrace.get_span_attrs()

    function_name = function_name({module, function}, name)
    function_arity_name = function_name({module, function, arity}, name)

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
          system_time: system_time,
          start_time_mono: start_time_mono,
          end_time_mono: end_time_mono
        })

        NewRelic.report_span(
          timestamp_ms: System.convert_time_unit(system_time, :native, :millisecond),
          duration_s: duration_s,
          name: metric_name,
          edge: [span: id, parent: parent_id],
          category: "http",
          attributes:
            Map.merge(span_attrs, %{
              "tracer.function": function_arity_name,
              "tracer.args": args,
              "tracer.reductions": reductions
            })
        )

        if NewRelic.Config.feature?(:extended_attributes) do
          NewRelic.incr_attributes(
            "external.#{host}.call_count": 1,
            "external.#{host}.duration_ms": duration_ms
          )
        end

        NewRelic.report_metric({:external, url, component, method}, duration_s: duration_s)

        Transaction.Reporter.track_metric({
          {:external, url, component, method},
          duration_s: duration_s
        })

      _ ->
        Transaction.Reporter.add_trace_segment(%{
          module: module,
          function: function,
          arity: arity,
          name: name,
          args: args,
          pid: pid,
          id: id,
          parent_id: parent_id,
          system_time: system_time,
          start_time_mono: start_time_mono,
          end_time_mono: end_time_mono
        })

        NewRelic.report_span(
          timestamp_ms: System.convert_time_unit(system_time, :native, :millisecond),
          duration_s: duration_s,
          name: function_arity_name,
          edge: [span: id, parent: parent_id],
          category: "http",
          attributes:
            Map.merge(span_attrs, %{
              "tracer.args": args,
              "tracer.reductions": reductions
            })
        )

        if NewRelic.Config.feature?(:extended_attributes) do
          NewRelic.incr_attributes(
            "external.#{function_name}.call_count": 1,
            "external.#{function_name}.duration_ms": duration_ms
          )
        end

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
         {system_time, start_time_mono, end_time_mono, child_duration_ms, reductions}
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
      system_time: system_time,
      start_time_mono: start_time_mono,
      end_time_mono: end_time_mono
    })

    NewRelic.report_span(
      timestamp_ms: System.convert_time_unit(system_time, :native, :millisecond),
      duration_s: duration_s,
      name: function_name,
      edge: [span: id, parent: parent_id],
      category: "generic",
      attributes:
        Map.merge(NewRelic.DistributedTrace.get_span_attrs(), %{
          "tracer.args": args,
          "tracer.reductions": reductions
        })
    )

    if NewRelic.Config.feature?(:extended_attributes) do
      NewRelic.incr_attributes(
        "function.#{function_name}.call_count": 1,
        "function.#{function_name}.duration_ms": duration_ms
      )
    end

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
      inspect(arguments, charlists: :as_lists, limit: 7, printable_limit: 10)
    else
      "[DISABLED]"
    end
  end

  defp duration_ms(start_time_mono, end_time_mono),
    do: System.convert_time_unit(end_time_mono - start_time_mono, :native, :microsecond) / 1000

  defp function_name({m, f}, f), do: "#{inspect(m)}.#{f}"
  defp function_name({m, f}, i), do: "#{inspect(m)}.#{f}:#{i}"
  defp function_name({m, f, a}, f), do: "#{inspect(m)}.#{f}/#{a}"
  defp function_name({m, f, a}, i), do: "#{inspect(m)}.#{f}:#{i}/#{a}"
end
