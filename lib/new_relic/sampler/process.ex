defmodule NewRelic.Sampler.Process do
  use GenServer

  # Takes samples of the state of requested processes at an interval

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()

    if NewRelic.Config.enabled?(),
      do: Process.send_after(self(), :report, NewRelic.Sampler.Reporter.random_sample_offset())

    {:ok, %{pids: %{}, previous: %{}}}
  end

  def sample_process, do: GenServer.cast(__MODULE__, {:sample_process, self()})

  def handle_cast({:sample_process, pid}, state) do
    state = store_pid(state.pids[pid], state, pid)
    {:noreply, state}
  end

  def handle_info(:report, state) do
    previous = record_samples(state)
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, %{state | previous: previous}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = %{
      state
      | pids: Map.delete(state.pids, pid),
        previous: Map.delete(state.previous, pid)
    }

    {:noreply, state}
  end

  def handle_call(:report, _from, state) do
    previous = record_samples(state)
    {:reply, :ok, %{state | previous: previous}}
  end

  def record_samples(state) do
    Enum.reduce(state.pids, %{}, fn {pid, true}, acc ->
      {current_sample, stats} = collect(pid, state.previous[pid])
      NewRelic.report_sample(:ProcessSample, stats)
      Map.put(acc, pid, current_sample)
    end)
  end

  def store_pid(true, state, _existing_pid), do: state

  def store_pid(nil, state, pid) do
    Process.monitor(pid)
    pids = Map.put(state.pids, pid, true)
    previous = Map.put(state.previous, pid, take_sample(pid))
    %{state | pids: pids, previous: previous}
  end

  def collect(pid, previous) do
    current_sample = take_sample(pid)
    stats = Map.merge(current_sample, delta(previous, current_sample))
    {current_sample, stats}
  end

  @kb 1024
  def take_sample(pid) do
    # http://erlang.org/doc/man/erlang.html#process_info-2
    info = Process.info(pid, [:message_queue_len, :memory, :reductions, :registered_name])

    %{
      pid: inspect(pid),
      memory_kb: info[:memory] / @kb,
      message_queue_length: info[:message_queue_len],
      name: parse(:name, info[:registered_name]) || inspect(pid),
      reductions: info[:reductions]
    }
  end

  defp delta(previous, current), do: %{reductions: current.reductions - previous.reductions}

  defp parse(:name, []), do: nil
  defp parse(:name, name), do: inspect(name)
end
