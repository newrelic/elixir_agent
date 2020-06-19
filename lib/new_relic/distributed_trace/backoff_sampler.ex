defmodule NewRelic.DistributedTrace.BackoffSampler do
  use GenServer
  alias NewRelic.Harvest.Collector.AgentRun

  # This GenServer tracks the sampling rate across sampling periods,
  # which is used to determine when to sample a Distributed Trace

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    trigger_next_cycle()
    {:ok, init_state()}
  end

  def init_state() do
    %{
      sampling_target: AgentRun.lookup(:sampling_target) || 10,
      cycle_number: 0,
      sampled_true_count: 0,
      decided_count: 0,
      decided_count_last: 0
    }
  end

  def sample?, do: GenServer.call(__MODULE__, :sample?)

  def handle_call(:sample?, _from, state) do
    {sampled, state} = calculate(state)
    {:reply, sampled, state}
  end

  def handle_info(:cycle, state) do
    trigger_next_cycle()
    {:noreply, cycle(state)}
  end

  def handle_info(:reset, _state) do
    {:noreply, init_state()}
  end

  def cycle(state) do
    %{
      state
      | cycle_number: state.cycle_number + 1,
        sampled_true_count: 0,
        decided_count: 0,
        decided_count_last: state.decided_count
    }
  end

  def calculate(state) do
    sampled = do_sample?(state)
    state = update_state(sampled, state)
    {sampled, state}
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
    Process.send_after(self(), :cycle, cycle_period)
  end

  def update_state(false = _sampled?, state) do
    %{state | decided_count: state.decided_count + 1}
  end

  def update_state(true = _sampled?, state) do
    %{
      state
      | decided_count: state.decided_count + 1,
        sampled_true_count: state.sampled_true_count + 1
    }
  end

  def random(0), do: 0
  def random(n), do: :rand.uniform(n)
end
