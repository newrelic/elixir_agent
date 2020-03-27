defmodule NewRelic.Sampler.Agent do
  use GenServer

  alias NewRelic.Transaction

  # Takes samples of the state of the Agent

  @moduledoc false

  def start_link do
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
      {:supportability, :agent, "ReporterCompleteActive"},
      value: length(Task.Supervisor.children(Transaction.TaskSupervisor))
    )
  end
end
