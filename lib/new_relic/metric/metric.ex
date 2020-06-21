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

  def merge(one, two) do
    %{
      one
      | call_count: one.call_count + two.call_count,
        max_call_time: max(one.max_call_time, two.max_call_time),
        min_call_time: calculate_min_call_time(one.min_call_time, two.min_call_time),
        sum_of_squares: one.sum_of_squares + two.sum_of_squares,
        total_call_time: one.total_call_time + two.total_call_time,
        total_exclusive_time: one.total_exclusive_time + two.total_exclusive_time
    }
  end

  defp calculate_min_call_time(cur, acc) when cur == 0 or acc == 0, do: max(cur, acc)
  defp calculate_min_call_time(cur, acc), do: min(cur, acc)
end
