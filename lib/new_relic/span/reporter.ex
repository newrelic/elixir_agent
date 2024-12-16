defmodule NewRelic.Span.Reporter do
  @moduledoc false

  def report_span(span) do
    case NewRelic.Config.feature?(:distributed_tracing) &&
           NewRelic.Config.feature(:infinite_tracing) do
      false -> :ignore
      :sampling -> NewRelic.Harvest.Collector.SpanEvent.Harvester.report_span(span)
      :infinite -> NewRelic.Harvest.TelemetrySdk.Spans.Harvester.report_span(span)
    end
  end
end
