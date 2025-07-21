defmodule NewRelic.DistributedTrace.BackoffSampler do
  use GenServer
  alias NewRelic.Harvest.Collector.AgentRun

  # This GenServer tracks the sampling rate across sampling periods,
  # which is used to determine when to sample a Distributed Trace.
  # State is stored in erlang `counters` which are super fast

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # Counter indexes
  @size 5
  @cycle_number 1
  @sampled_true_count 2
  @decided_count 3
  @decided_count_last 4
  @sampling_target 5

  def init(:ok) do
    NewRelic.sample_process()

    :persistent_term.put({__MODULE__, :counter}, new(@size, []))
    put(@sampling_target, AgentRun.lookup(:sampling_target) || 10)

    trigger_next_cycle()
    {:ok, %{}}
  end

  def sample? do
    calculate(%{
      cycle_number: get(@cycle_number),
      sampled_true_count: get(@sampled_true_count),
      decided_count: get(@decided_count),
      decided_count_last: get(@decided_count_last),
      sampling_target: get(@sampling_target)
    })
  end

  @priority_multiplier 2
  def priority_sample? do
    result =
      do_sample?(%{
        cycle_number: get(@cycle_number),
        sampled_true_count: get(@sampled_true_count),
        decided_count: get(@decided_count),
        decided_count_last: get(@decided_count_last),
        sampling_target: get(@sampling_target) * @priority_multiplier
      })

    if result == true, do: update_state(true)
    result
  end

  def handle_info(:cycle, state) do
    cycle()
    trigger_next_cycle()
    {:noreply, state}
  end

  def reset() do
    put(@cycle_number, 0)
    put(@decided_count_last, 0)
    put(@decided_count, 0)
    put(@sampled_true_count, 0)
  end

  def cycle() do
    incr(@cycle_number)
    put(@decided_count_last, get(@decided_count))
    put(@decided_count, 0)
    put(@sampled_true_count, 0)
  end

  defp calculate(state) do
    sampled = do_sample?(state)
    update_state(sampled)
    sampled
  end

  def do_sample?(%{
        cycle_number: 0,
        sampled_true_count: sampled_true_count,
        sampling_target: sampling_target
      }) do
    sampled_true_count < sampling_target
  end

  def do_sample?(%{
        sampled_true_count: sampled_true_count,
        sampling_target: sampling_target,
        decided_count_last: decided_count_last
      })
      when sampled_true_count < sampling_target do
    random(decided_count_last) < sampling_target
  end

  def do_sample?(%{
        sampled_true_count: sampled_true_count,
        sampling_target: sampling_target,
        decided_count: decided_count
      }) do
    random(decided_count) <
      :math.pow(sampling_target, sampling_target / sampled_true_count) -
        :math.pow(sampling_target, 0.5)
  end

  def trigger_next_cycle() do
    cycle_period = AgentRun.lookup(:sampling_target_period) || 60_000
    Process.send_after(__MODULE__, :cycle, cycle_period)
  end

  defp update_state(false = _sampled?) do
    incr(@decided_count)
  end

  defp update_state(true = _sampled?) do
    incr(@decided_count)
    incr(@sampled_true_count)
  end

  defp random(0), do: 0
  defp random(n), do: :rand.uniform(n)

  @compile {:inline, new: 2, incr: 1, put: 2, get: 1, pt: 0}
  defp new(size, opts), do: :counters.new(size, opts)
  defp incr(index), do: :counters.add(pt(), index, 1)
  defp put(index, value), do: :counters.put(pt(), index, value)
  defp get(index), do: :counters.get(pt(), index)
  defp pt(), do: :persistent_term.get({__MODULE__, :counter})
end
