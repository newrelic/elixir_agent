defmodule NewRelic.Tracer.Direct do
  @moduledoc false

  @max_open_span_count Application.compile_env(:new_relic, :max_open_span_count, 20)

  def start_span(id, name, options \\ []) do
    case Process.get(:nr_open_span_count, 0) do
      over when over >= @max_open_span_count ->
        Process.put(:nr_open_span_count, over + 1)
        NewRelic.incr_attributes(skipped_span_count: 1)

      under ->
        Process.put(:nr_open_span_count, under + 1)

        system_time = Keyword.get(options, :system_time, System.system_time())
        monotonic_time = Keyword.get(options, :monotonic_time, System.monotonic_time())
        attributes = Keyword.get(options, :attributes, []) |> Map.new()

        {span, previous_span, previous_span_attrs} =
          NewRelic.DistributedTrace.set_current_span(
            label: id,
            ref: make_ref()
          )

        Process.put(
          {:nr_span, id},
          {name, system_time, monotonic_time, attributes, {span, previous_span, previous_span_attrs}}
        )
    end

    :ok
  end

  def stop_span(id, options \\ []) do
    case Process.delete({:nr_span, id}) do
      nil ->
        :no_such_span

      {name, system_time, monotonic_start_time, start_attributes, {span, previous_span, previous_span_attrs}} ->
        Process.put(:nr_open_span_count, Process.get(:nr_open_span_count) - 1)

        {duration, duration_s} =
          case Keyword.get(options, :duration) do
            nil ->
              duration = System.monotonic_time() - monotonic_start_time
              {duration, System.convert_time_unit(duration, :native, :microsecond) / 1_000_000}

            duration ->
              {duration, System.convert_time_unit(duration, :native, :microsecond) / 1_000_000}
          end

        name = Keyword.get(options, :name, name)
        timestamp_ms = System.convert_time_unit(system_time, :native, :millisecond)
        stop_attributes = Keyword.get(options, :attributes, []) |> Map.new()

        attributes =
          start_attributes
          |> Map.merge(NewRelic.DistributedTrace.get_span_attrs())
          |> Map.merge(stop_attributes)

        {primary_name, secondary_name} =
          case name do
            {primary_name, secondary_name} -> {primary_name, secondary_name}
            name -> {name, ""}
          end

        NewRelic.Transaction.Reporter.add_trace_segment(%{
          primary_name: primary_name,
          secondary_name: secondary_name,
          attributes: attributes,
          pid: self(),
          id: span,
          parent_id: previous_span || :root,
          start_time: system_time,
          duration: duration
        })

        NewRelic.report_span(
          timestamp_ms: timestamp_ms,
          duration_s: duration_s,
          name: primary_name,
          edge: [span: span, parent: previous_span || :root],
          category: "generic",
          attributes: attributes
        )

        if NewRelic.Config.feature?(:extended_attributes) do
          NewRelic.incr_attributes(
            "span.#{primary_name}.call_count": 1,
            "span.#{primary_name}.duration_ms": duration
          )
        end

        NewRelic.report_metric({:function, primary_name}, duration_s: duration_s)

        NewRelic.DistributedTrace.reset_span(
          previous_span: previous_span,
          previous_span_attrs: previous_span_attrs
        )
    end

    :ok
  end
end
