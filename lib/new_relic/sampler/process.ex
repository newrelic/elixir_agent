defmodule NewRelic.Sampler.Process do
  use GenServer
  @kb 1024

  # Takes samples of the state of requested processes at an interval

  @moduledoc false

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    if NewRelic.Config.enabled?(), do: send(self(), :report)
    {:ok, %{pids: MapSet.new(), last: %{}}}
  end

  def sample_process, do: GenServer.cast(__MODULE__, {:sample_process, self()})

  def handle_cast({:sample_process, pid}, state) do
    Process.monitor(pid)
    pids = MapSet.put(state.pids, pid)
    last = Map.put(state.last, pid, take_sample(pid))
    {:noreply, %{state | pids: pids, last: last}}
  end

  def handle_info(:report, state) do
    last = record_samples(state)
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, %{state | last: last}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | pids: MapSet.delete(state.pids, pid)}}
  end

  def handle_call(:report, _from, state) do
    last = record_samples(state)
    {:reply, :ok, %{state | last: last}}
  end

  def record_samples(state) do
    Enum.reduce(state.pids, %{}, fn pid, acc ->
      {current_sample, stats} = collect(pid, state.last[pid])
      NewRelic.report_sample(:ProcessSample, stats)
      Map.put(acc, pid, current_sample)
    end)
  end

  def collect(pid, last) do
    current_sample = take_sample(pid)
    stats = Map.merge(current_sample, delta(last, current_sample))
    {current_sample, stats}
  end

  def take_sample(pid) do
    # http://erlang.org/doc/man/erlang.html#process_info-2
    info = :erlang.process_info(pid, [:message_queue_len, :memory, :reductions, :registered_name])

    %{
      pid: inspect(pid),
      memory_kb: info[:memory] / @kb,
      message_queue_length: info[:message_queue_len],
      name: parse(:name, info[:registered_name]) || inspect(pid),
      reductions: info[:reductions]
    }
  end

  defp delta(last, current), do: %{reductions: current.reductions - last.reductions}

  defp parse(:name, []), do: nil
  defp parse(:name, name), do: inspect(name)
end
