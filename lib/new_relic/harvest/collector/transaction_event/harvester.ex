defmodule NewRelic.Harvest.Collector.TransactionEvent.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector
  alias NewRelic.Transaction.Event
  alias NewRelic.Util.PriorityQueue

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       sampling: %{
         reservoir_size: Collector.AgentRun.lookup(:transaction_event_reservoir_size, 100),
         events_seen: 0
       },
       events: PriorityQueue.new()
     }}
  end

  # API

  def report_event(%Event{} = event),
    do:
      Collector.TransactionEvent.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, event})

  def gather_harvest,
    do:
      Collector.TransactionEvent.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
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

  defp store_event(%{sampling: %{reservoir_size: size}} = state, event) do
    key = event.user_attributes[:priority] || :rand.uniform() |> Float.round(6)
    %{state | events: PriorityQueue.insert(state.events, size, key, event)}
  end

  defp store_sampling(%{sampling: sampling} = state),
    do: %{state | sampling: Map.update!(sampling, :events_seen, &(&1 + 1))}

  defp send_harvest(state) do
    events = build_payload(state)

    Collector.Protocol.transaction_event([
      Collector.AgentRun.agent_run_id(),
      state.sampling,
      events
    ])

    log_harvest(length(events), state.sampling.events_seen, state.sampling.reservoir_size)
  end

  defp log_harvest(harvest_size, events_seen, reservoir_size) do
    NewRelic.report_metric({:supportability, "AnalyticEventData"}, harvest_size: harvest_size)

    NewRelic.report_metric({:supportability, "AnalyticEventData"},
      events_seen: events_seen,
      reservoir_size: reservoir_size
    )

    NewRelic.log(
      :debug,
      "Completed Transaction Event harvest - " <>
        "size: #{harvest_size}, seen: #{events_seen}, max: #{reservoir_size}"
    )
  end

  defp build_payload(state) do
    state.events
    |> PriorityQueue.values()
    |> Event.format_events()
  end
end
