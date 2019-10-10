defmodule NewRelic.Util.RequestStart do
  @moduledoc false

  def parse("t=" <> time), do: parse(time)

  def parse(time) do
    with {time, _} <- Float.parse(time),
         :next <- check_time_unit(time / 1000_000),
         :next <- check_time_unit(time / 1000),
         :next <- check_time_unit(time) do
      :error
    else
      {:ok, queue_start_s} -> {:ok, queue_start_s}
      _ -> :error
    end
  end

  @earliest ~N[2000-01-01 00:00:00]
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.to_unix()

  defp check_time_unit(time) do
    (time > @earliest && {:ok, time}) || :next
  end
end
