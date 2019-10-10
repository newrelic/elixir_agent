defmodule Util.RequestQueueTime do
  @moduledoc false

  def parse("t=" <> time), do: parse(time)

  def parse(time_string) do
    with {time, _} <- Float.parse(time_string),
         :next <- determine_time_unit(time / 1000_000),
         :next <- determine_time_unit(time / 1000),
         :next <- determine_time_unit(time) do
      :error
    else
      {:ok, queue_start_s} -> {:ok, queue_start_s}
      _ -> :error
    end
  end

  @earliest_acceptable_time 946_684_800
  defp determine_time_unit(time) do
    (time > @earliest_acceptable_time && {:ok, time}) || :next
  end
end
