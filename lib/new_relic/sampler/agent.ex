defmodule NewRelic.Sampler.Agent do
  use GenServer

  # Takes samples of the state of the Agent

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    if NewRelic.Config.enabled?(),
      do: Process.send_after(self(), :report, NewRelic.Sampler.Reporter.random_sample_offset())

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

  defp record_sample do
    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Process/ActiveCount"},
      value: NewRelic.Transaction.Sidecar.counter()
    )

    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Stores/ContextStore/Size"},
      value: ets_size(NewRelic.Transaction.Sidecar.ContextStore)
    )

    NewRelic.report_metric(
      {:supportability, :agent, "Sidecar/Stores/LookupStore/Size"},
      value: ets_size(NewRelic.Transaction.Sidecar.LookupStore)
    )

    NewRelic.report_metric(
      {:supportability, :agent, "ErlangTrace/Restarts"},
      value: NewRelic.Transaction.ErlangTraceManager.restart_count()
    )
  end

  defp ets_size(table) do
    :ets.info(table, :size)
  rescue
    ArgumentError -> nil
  end
end
