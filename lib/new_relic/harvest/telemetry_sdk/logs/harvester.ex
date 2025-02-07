defmodule NewRelic.Harvest.TelemetrySdk.Logs.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.TelemetrySdk

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
         reservoir_size: Application.get_env(:new_relic_agent, :log_reservoir_size, 5_000),
         logs_seen: 0
       },
       logs: []
     }}
  end

  # API

  def report_log(log),
    do:
      TelemetrySdk.Logs.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, log})

  def gather_harvest,
    do:
      TelemetrySdk.Logs.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, log}, state) do
    state =
      state
      |> store_log(log)
      |> store_sampling

    {:noreply, state}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_log_data(state.logs), state}
  end

  # Helpers

  defp store_log(%{sampling: %{logs_seen: seen, reservoir_size: size}} = state, log)
       when seen < size,
       do: %{state | logs: [log | state.logs]}

  defp store_log(state, _log),
    do: state

  defp store_sampling(%{sampling: sampling} = state),
    do: %{state | sampling: Map.update!(sampling, :logs_seen, &(&1 + 1))}

  defp send_harvest(state) do
    TelemetrySdk.API.log(build_log_data(state.logs))
    log_harvest(length(state.logs), state.sampling.logs_seen, state.sampling.reservoir_size)
  end

  defp log_harvest(harvest_size, logs_seen, reservoir_size) do
    NewRelic.log(
      :debug,
      "Completed TelemetrySdk.Logs harvest - " <>
        "size: #{harvest_size}, seen: #{logs_seen}, max: #{reservoir_size}"
    )
  end

  defp build_log_data(logs) do
    [
      %{
        logs: logs,
        common: common()
      }
    ]
  end

  defp common() do
    %{
      attributes: NewRelic.LogsInContext.linking_metadata()
    }
  end
end
