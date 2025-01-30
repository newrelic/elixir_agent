defmodule NewRelic.Aggregate.Reporter do
  use GenServer
  alias NewRelic.Aggregate

  # This GenServer collects aggregate metric measurements, aggregates them,
  # and reports them to the Harvester at the defined sample_cycle

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    if NewRelic.Config.enabled?(), do: send(self(), :report)
    {:ok, %{}}
  end

  def report_aggregate(meta, values), do: GenServer.cast(__MODULE__, {:aggregate, meta, values})

  def handle_cast({:aggregate, meta, values}, state) do
    metric =
      state
      |> Map.get(meta, %Aggregate{meta: meta})
      |> Aggregate.merge(values)

    {:noreply, Map.put(state, meta, metric)}
  end

  def handle_info(:report, state) do
    record_aggregates(state)
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, %{}}
  end

  def handle_call(:report, _from, state) do
    record_aggregates(state)
    {:reply, :ok, %{}}
  end

  defp record_aggregates(state) do
    Enum.each(state, fn {_meta, metric} ->
      NewRelic.report_custom_event(aggregate_event_type(), Aggregate.annotate(metric))
    end)
  end

  defp aggregate_event_type,
    do: Application.get_env(:new_relic_agent, :aggregate_event_type, "ElixirAggregate")
end
