defmodule NewRelic.Harvest.Collector.ErrorTrace.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector
  alias NewRelic.Error.Trace

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       error_traces_seen: 0,
       error_traces: []
     }}
  end

  # API

  def report_error(%Trace{} = trace),
    do:
      Collector.ErrorTrace.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, trace})

  def gather_harvest,
    do:
      Collector.ErrorTrace.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  # Server

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, trace}, state) do
    state =
      state
      |> store_error(trace)

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

  @reservoir_size 20

  defp store_error(%{error_traces_seen: seen} = state, _trace)
       when seen >= @reservoir_size do
    %{
      state
      | error_traces_seen: state.error_traces_seen + 1
    }
  end

  defp store_error(state, trace) do
    %{
      state
      | error_traces_seen: state.error_traces_seen + 1,
        error_traces: [trace | state.error_traces]
    }
  end

  defp send_harvest(state) do
    errors = build_payload(state)
    Collector.Protocol.error([Collector.AgentRun.agent_run_id(), errors])
    log_harvest(length(errors), state.error_traces_seen)
  end

  defp log_harvest(harvest_size, events_seen) do
    NewRelic.report_metric({:supportability, "ErrorData"}, harvest_size: harvest_size)

    NewRelic.report_metric({:supportability, "ErrorData"},
      events_seen: events_seen,
      reservoir_size: @reservoir_size
    )

    NewRelic.log(
      :debug,
      "Completed Error Trace harvest - " <>
        "size: #{harvest_size}, seen: #{events_seen}, max: #{@reservoir_size}"
    )
  end

  defp build_payload(state), do: state.error_traces |> Enum.uniq() |> Trace.format_errors()
end
