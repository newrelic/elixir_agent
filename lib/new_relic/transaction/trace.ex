defmodule NewRelic.Transaction.Trace do
  defstruct start_time: nil,
            metric_name: nil,
            request_url: nil,
            attributes: %{},
            segments: [],
            duration: nil,
            cat_guid: "",
            reserved_for_future_use: nil,
            force_persist_flag: false,
            xray_session_id: nil,
            synthetics_resource_id: ""

  @moduledoc false

  defmodule Segment do
    defstruct relative_start_time: nil,
              relative_end_time: nil,
              metric_name: nil,
              attributes: %{},
              children: [],
              class_name: nil,
              method_name: nil,
              pid: nil

    @moduledoc false
  end

  @unused_map %{}

  def format_traces(traces) do
    Enum.map(traces, &format_trace/1)
  end

  def format_trace(%__MODULE__{} = trace) do
    trace_segments = format_segments(trace)
    trace_details = [trace.start_time, @unused_map, @unused_map, trace_segments, trace.attributes]

    [
      trace.start_time,
      trace.duration,
      trace.metric_name,
      trace.request_url,
      trace_details,
      trace.cat_guid,
      trace.reserved_for_future_use,
      trace.force_persist_flag,
      trace.xray_session_id,
      trace.synthetics_resource_id
    ]
  end

  def format_segments(%{
        segments: [first_segment | _] = segments,
        duration: duration,
        metric_name: metric_name
      }) do
    [
      0,
      duration,
      "ROOT",
      first_segment.attributes,
      [
        [
          0,
          duration,
          metric_name,
          first_segment.attributes,
          Enum.map(segments, &format_child_segments/1)
        ]
      ]
    ]
  end

  def format_child_segments(%Segment{} = segment) do
    [
      segment.relative_start_time,
      segment.relative_end_time,
      segment.metric_name,
      segment.attributes,
      Enum.map(segment.children, &format_child_segments/1),
      segment.class_name,
      segment.method_name
    ]
  end
end
