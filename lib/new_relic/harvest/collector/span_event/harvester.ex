defmodule NewRelic.Harvest.Collector.SpanEvent.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.DistributedTrace
  alias NewRelic.Harvest.Collector
  alias NewRelic.Span.Event
  alias NewRelic.Util.PriorityQueue

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       sampling: %{
         reservoir_size: Collector.AgentRun.lookup(:span_event_reservoir_size),
         events_seen: 0
       },
       events: PriorityQueue.new()
     }}
  end

  # API

  # Label is any term that identifies the thing the span represents
  #  ex: {m, f, a} for a function call
  # Reference identifies the unique instance of the span
  #  ex: make_ref()

  @type label :: any
  @type span :: {label, reference}
  @type parent :: {label, reference} | :root

  def report_span(
        timestamp_ms: timestamp_ms,
        duration_s: duration_s,
        name: name,
        edge: [span: _span, parent: _parent] = edge,
        category: category,
        attributes: attributes
      ) do
    %Event{
      timestamp: timestamp_ms,
      duration: duration_s,
      name: name,
      category: category,
      category_attributes: attributes
    }
    |> report_span_event(DistributedTrace.get_tracing_context(), edge)
  end

  def report_span_event(%Event{} = _event, nil = _context, _mfa), do: :no_transaction

  def report_span_event(%Event{} = _event, %DistributedTrace.Context{sampled: false}, _mfa),
    do: :not_sampled

  def report_span_event(
        %Event{} = event,
        %DistributedTrace.Context{sampled: true} = context,
        span: span,
        parent: parent
      ) do
    event
    |> Map.merge(%{
      guid: generate_guid(span),
      parent_id: generate_guid(parent),
      trace_id: context.trace_id,
      transaction_id: context.guid,
      sampled: true,
      priority: context.priority
    })
    |> report_span_event()
  end

  def report_span_event(%Event{} = event),
    do:
      Collector.SpanEvent.HarvestCycle
      |> Collector.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, event})

  def gather_harvest,
    do:
      Collector.SpanEvent.HarvestCycle
      |> Collector.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  # Server

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, event}, state) do
    state =
      state
      |> store_event(event)
      |> store_sampling

    {:noreply, state}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_payload(state), state}
  end

  # Helpers

  def store_event(%{sampling: %{reservoir_size: size}} = state, %{priority: key} = event),
    do: %{state | events: PriorityQueue.insert(state.events, size, key, event)}

  def store_sampling(%{sampling: sampling} = state),
    do: %{state | sampling: Map.update!(sampling, :events_seen, &(&1 + 1))}

  def send_harvest(state) do
    spans = build_payload(state)

    Collector.Protocol.span_event([
      Collector.AgentRun.agent_run_id(),
      state.sampling,
      spans
    ])

    log_harvest(length(spans))
  end

  def generate_guid(:root), do: DistributedTrace.generate_guid(pid: self())

  def generate_guid({label, ref}),
    do: DistributedTrace.generate_guid(pid: self(), label: label, ref: ref)

  def log_harvest(harvest_size) do
    NewRelic.report_metric({:supportability, SpanEvent}, harvest_size: harvest_size)
    NewRelic.log(:debug, "Completed Span Event harvest - size: #{harvest_size}")
  end

  def build_payload(state) do
    state.events
    |> PriorityQueue.values()
    |> Event.format_events()
  end
end
