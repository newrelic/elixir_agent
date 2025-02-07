defmodule NewRelic.Span.Event do
  # Struct for a Span Event
  #
  # * trace_id: Distributed Trace ID
  #   - trace_id from Transaction
  # * guid: Segment Identifier
  # * parent_id: Segment's Parent's GUID
  #   - id of incoming DT payload OR `guid` of parent segment
  # * transaction_id: Transaction's guid
  # * timestamp: Segment start in unix timestamp milliseconds
  # * duration: Segment elapsed in seconds
  # * category: http | datastore | generic
  # * entry_point: Only included if span is First segment

  defstruct type: "Span",
            trace_id: nil,
            guid: nil,
            parent_id: nil,
            transaction_id: nil,
            sampled: nil,
            priority: nil,
            timestamp: nil,
            duration: nil,
            name: nil,
            category: nil,
            entry_point: false,
            category_attributes: %{}

  @moduledoc false

  def format_events(spans) do
    Enum.map(spans, &format_event/1)
  end

  defp format_event(%__MODULE__{} = span) do
    intrinsics =
      %{
        type: span.type,
        traceId: span.trace_id,
        guid: span.guid,
        parentId: span.parent_id,
        transactionId: span.transaction_id,
        sampled: span.sampled,
        priority: span.priority,
        timestamp: span.timestamp,
        duration: span.duration,
        name: span.name,
        category: span.category
      }
      |> merge_category_attributes(span.category_attributes)

    intrinsics =
      case span.entry_point do
        true -> Map.merge(intrinsics, %{"nr.entryPoint": true})
        false -> intrinsics
      end

    [
      intrinsics,
      _user = %{},
      _agent = %{}
    ]
  end

  def merge_category_attributes(%{category: "http"} = span, category_attributes) do
    {category, custom} = Map.split(category_attributes, [:url, :method, :component])

    span
    |> Map.merge(%{
      "http.url": category[:url] || "url",
      "http.method": category[:method] || "method",
      component: category[:component] || "component",
      "span.kind": "client"
    })
    |> Map.merge(custom)
    |> NewRelic.Util.coerce_attributes()
  end

  def merge_category_attributes(%{category: "datastore"} = span, category_attributes) do
    {category, custom} =
      Map.split(category_attributes, [:statement, :instance, :address, :hostname, :component])

    span
    |> Map.merge(%{
      "db.statement": category[:statement] || "statement",
      "db.instance": category[:instance] || "instance",
      "peer.address": category[:address] || "address",
      "peer.hostname": category[:hostname] || "hostname",
      component: category[:component] || "component",
      "span.kind": "client"
    })
    |> Map.merge(custom)
    |> NewRelic.Util.coerce_attributes()
  end

  def merge_category_attributes(span, category_attributes),
    do:
      Map.merge(
        span,
        NewRelic.Util.coerce_attributes(category_attributes),
        # Don't overwrite existing span keys with custom values
        fn _k, v1, _v2 -> v1 end
      )
end
