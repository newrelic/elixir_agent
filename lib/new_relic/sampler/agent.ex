defmodule NewRelic.Sampler.Agent do
  use GenServer

  alias NewRelic.Transaction

  # Takes samples of the state of the Agent

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    if NewRelic.Config.enabled?(),
      do: Process.send_after(self(), :report, NewRelic.Sampler.Reporter.random_offset())

    {:ok, %{}}
  end

  def handle_info(:report, state) do
    record_sample()
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, state}
  end

  def handle_call(:report, _from, state) do
    record_sample()
    {:reply, :ok, state}
  end

  def record_sample do
    NewRelic.report_metric(
      {:supportability, :agent, "ReporterCollectingSize"},
      value: ets_size(NewRelic.Transaction.Reporter.Collecting)
    )

    NewRelic.report_metric(
      {:supportability, :agent, "ReporterTrackingSize"},
      value: ets_size(NewRelic.Transaction.Reporter.Tracking)
    )

    NewRelic.report_metric(
      {:supportability, :agent, "ReporterCompleteTasksActive"},
      value: length(Task.Supervisor.children(Transaction.TaskSupervisor))
    )
  end

  def ets_size(table) do
    :ets.info(table, :size)
  rescue
    ArgumentError -> nil
  end
end
