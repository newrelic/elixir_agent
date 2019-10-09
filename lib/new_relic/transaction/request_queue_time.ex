defmodule NewRelic.Transaction.RequestQueueTime do
  @moduledoc false

  # Any timestamps before this are thrown out and the parser
  # will try again with a larger unit (2000/1/1 UTC)
  @earliest_acceptable_time 946_684_800 * 1_000_000
  @multipliers [1, 1_000, 1_000_000]

  # Return in seconds?
  def timestamp_to_us("t=" <> time) do
    with {:ok, numeric} <- time_to_numeric(time),
         {:ok, microseconds} <- time_to_microseconds(numeric) do
      {:ok, min(microseconds, now_us())}
    end
  end

  def timestamp_to_us(_), do: {:error, "invalid request queueing format, expected `t=\d+`"}

  defp time_to_microseconds(numeric),
    do:
      Enum.reduce_while(
        @multipliers,
        {:error, "timestamp '#{numeric}' is not valid"},
        fn multiplier, acc ->
          time = numeric * multiplier

          if time > @earliest_acceptable_time do
            {:halt, {:ok, time}}
          else
            {:cont, acc}
          end
        end
      )

  defp time_to_numeric(time) do
    try do
      {:ok, String.to_integer(time)}
    rescue
      ArgumentError ->
        time_to_numeric_f(time)
    end
  end

  defp time_to_numeric_f(time) do
    try do
      {:ok, String.to_float(time)}
    rescue
      ArgumentError ->
        {:error, @invalid_format}
    end
  end

  defp now_us(), do: System.system_time(:microsecond)
end
