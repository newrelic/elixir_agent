defmodule NewRelic.Sampler.Ets do
  use GenServer
  @kb 1024
  @word_size :erlang.system_info(:wordsize)

  # Takes samples of the state of ETS tables

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()

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

  defp record_sample, do: Enum.map(named_tables(), &record_sample/1)

  @size_threshold 500
  def record_sample(table) do
    case take_sample(table) do
      :undefined -> :ignore
      %{size: size} when size < @size_threshold -> :ignore
      stat -> NewRelic.report_sample(:EtsStat, stat)
    end
  end

  defp named_tables, do: Enum.reject(:ets.all(), &is_reference/1)

  defp take_sample(table) do
    with words when is_number(words) <- :ets.info(table, :memory),
         size when is_number(size) <- :ets.info(table, :size) do
      %{table_name: inspect(table), memory_kb: round(words * @word_size) / @kb, size: size}
    else
      :undefined -> :undefined
    end
  end
end
