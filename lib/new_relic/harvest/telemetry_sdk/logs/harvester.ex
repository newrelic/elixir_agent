defmodule NewRelic.Harvest.TelemetrySdk.Logs.Harvester do
  use GenServer

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
    {:noreply, %{state | logs: [log | state.logs]}}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_log_data(state.logs), state}
  end

  def send_harvest(state) do
    TelemetrySdk.API.post(
      :log,
      build_log_data(state.logs)
    )

    log_harvest(length(state.logs))
  end

  def log_harvest(harvest_size) do
    NewRelic.log(:debug, "Completed Log harvest - size: #{harvest_size}")
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
