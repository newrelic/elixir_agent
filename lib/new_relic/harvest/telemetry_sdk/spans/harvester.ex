defmodule NewRelic.Harvest.TelemetrySdk.Spans.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk
  alias NewRelic.DistributedTrace

  def start_link(_) do
    GenServer.start_link(__MODULE__, mode: NewRelic.Config.feature(:infinite_tracing))
  end

  def init(mode: mode) do
    {:ok,
     %{
       trace_mode: mode,
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       sampling: %{
         reservoir_size: Application.get_env(:new_relic_agent, :span_reservoir_size, 5_000),
         spans_seen: 0
       },
       spans: []
     }}
  end

  # API

  def report_span(
        timestamp_ms: timestamp_ms,
        duration_s: duration_s,
        name: name,
        edge: [span: span, parent: parent],
        category: category,
        attributes: attributes
      ) do
    with %{trace_id: trace_id, guid: guid} <-
           DistributedTrace.get_tracing_context() do
      report_span(%{
        id: generate_guid(span),
        timestamp: timestamp_ms,
        "trace.id": trace_id,
        attributes:
          %{
            name: name,
            category: category,
            "parent.id": generate_guid(parent),
            transactionId: guid,
            "duration.ms": duration_s * 1000
          }
          |> NewRelic.Span.Event.merge_category_attributes(attributes)
      })
    end
  end

  def report_span(
        %NewRelic.Span.Event{
          guid: guid,
          trace_id: trace_id,
          timestamp: timestamp
        } = span
      ) do
    report_span(%{
      id: guid,
      timestamp: timestamp,
      "trace.id": trace_id,
      attributes:
        %{
          name: span.name,
          category: span.category,
          transactionId: span.transaction_id,
          "nr.entryPoint": span.entry_point,
          "duration.ms": span.duration * 1000,
          "parent.id": span.parent_id
        }
        |> NewRelic.Span.Event.merge_category_attributes(span.category_attributes)
    })
  end

  def report_span(span) do
    with :infinite <- NewRelic.Config.feature(:infinite_tracing) do
      NewRelic.report_metric({:supportability, :infinite_tracing}, spans_seen: 1)
    end

    TelemetrySdk.Spans.HarvestCycle
    |> Harvest.HarvestCycle.current_harvester()
    |> GenServer.cast({:report, span})
  end

  def gather_harvest,
    do:
      TelemetrySdk.Spans.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, span}, state) do
    state =
      state
      |> store_sampling
      |> store_span(span)

    {:noreply, state}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_span_data(state.spans), state}
  end

  # Helpers

  defp store_span(
         %{trace_mode: :infinite, sampling: %{spans_seen: seen, reservoir_size: size}} = state,
         span
       )
       when seen == size do
    Harvest.HarvestCycle.cycle(TelemetrySdk.Spans.HarvestCycle)
    %{state | spans: [span | state.spans]}
  end

  defp store_span(%{trace_mode: :infinite} = state, span) do
    %{state | spans: [span | state.spans]}
  end

  defp store_span(%{sampling: %{spans_seen: seen, reservoir_size: size}} = state, span)
       when seen < size do
    %{state | spans: [span | state.spans]}
  end

  defp store_span(state, _span),
    do: state

  defp store_sampling(%{sampling: sampling} = state),
    do: %{state | sampling: Map.update!(sampling, :spans_seen, &(&1 + 1))}

  defp send_harvest(state) do
    TelemetrySdk.API.span(build_span_data(state.spans))

    log_harvest(
      length(state.spans),
      state.sampling.spans_seen,
      state.sampling.reservoir_size,
      state.trace_mode
    )
  end

  defp log_harvest(harvest_size, spans_seen, reservoir_size, trace_mode) do
    with :infinite <- trace_mode do
      NewRelic.report_metric({:supportability, :infinite_tracing}, harvest_size: harvest_size)
    end

    NewRelic.log(
      :debug,
      "Completed TelemetrySdk.Span harvest - " <>
        "mode: #{trace_mode}, size: #{harvest_size}, seen: #{spans_seen}, max: #{reservoir_size}"
    )
  end

  defp generate_guid(:root), do: DistributedTrace.generate_guid(pid: self())

  defp generate_guid({label, ref}),
    do: DistributedTrace.generate_guid(pid: self(), label: label, ref: ref)

  defp build_span_data(spans) do
    [
      %{
        spans: spans,
        common: common()
      }
    ]
  end

  defp common() do
    %{
      attributes: NewRelic.Harvest.Collector.AgentRun.entity_metadata()
    }
  end
end
