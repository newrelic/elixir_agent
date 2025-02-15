defmodule NewRelic.Aggregate do
  defstruct meta: %{}, values: %{}

  # A metric-like struct for reporting aggregate data as events to NRDB

  @moduledoc false

  def merge(aggregate, values) do
    new_values = Map.merge(aggregate.values, values, fn _k, v1, v2 -> v1 + v2 end)
    %{aggregate | values: new_values}
  end

  def annotate(aggregate) do
    aggregate.values
    |> Map.merge(averages(aggregate.values))
    |> Map.merge(aggregate.meta)
    |> Map.put(:category, :Metric)
  end

  defp averages(%{call_count: call_count} = values) do
    values
    |> Enum.reject(fn {key, _value} -> key == :call_count end)
    |> Map.new(fn {key, value} -> {:"avg_#{key}", value / call_count} end)
  end

  defp averages(_values), do: %{}
end
