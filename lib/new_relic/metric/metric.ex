defmodule NewRelic.Metric do
  defstruct name: "",
            scope: "",
            call_count: 0,
            max_call_time: 0,
            min_call_time: 0,
            sum_of_squares: 0,
            total_call_time: 0,
            total_exclusive_time: 0

  @moduledoc false

  def reduce(metrics),
    do:
      Enum.reduce(
        metrics,
        &%{
          &2
          | call_count: &1.call_count + &2.call_count,
            max_call_time: max(&1.max_call_time, &2.max_call_time),
            min_call_time: calculate_min_call_time(&1.min_call_time, &2.min_call_time),
            sum_of_squares: &1.sum_of_squares + &2.sum_of_squares,
            total_call_time: &1.total_call_time + &2.total_call_time,
            total_exclusive_time: &1.total_exclusive_time + &2.total_exclusive_time
        }
      )

  defp calculate_min_call_time(cur, acc) when cur == 0 or acc == 0, do: max(cur, acc)
  defp calculate_min_call_time(cur, acc), do: min(cur, acc)
end
