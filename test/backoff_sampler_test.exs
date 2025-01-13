defmodule BackoffSamplerTest do
  use ExUnit.Case
  alias NewRelic.DistributedTrace.BackoffSampler

  test "Backoff behavior as best as we can" do
    # This is testing an inherently random algorithm

    BackoffSampler.reset()

    # Target is 10, so it will sample the first 10
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()

    # The rest will be dropped
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()

    BackoffSampler.cycle()

    # Next cycle it will adjust and take some, but not all
    decisions = [
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?()
    ]

    assert true in decisions
    assert false in decisions

    # Next cycle it will adjust and take some, but not all
    decisions = [
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?()
    ]

    assert true in decisions
    assert false in decisions
  end

  test "all calculations at least can run" do
    assert BackoffSampler.do_sample?(%{
             cycle_number: 0,
             sampled_true_count: 0,
             sampling_target: 10
           })

    refute BackoffSampler.do_sample?(%{
             cycle_number: 10,
             sampled_true_count: 5,
             sampling_target: 10,
             decided_count_last: 5000
           })

    refute BackoffSampler.do_sample?(%{
             cycle_number: 10,
             sampled_true_count: 100,
             sampling_target: 10,
             decided_count: 5000
           })
  end

  test "handle when we need rand(0)" do
    BackoffSampler.do_sample?(%{
      cycle_number: 1,
      sampled_true_count: 0,
      sampling_target: 10,
      decided_count_last: 0
    })
  end

  test "cycles trigger" do
    Application.put_env(:new_relic_agent, :sampling_target_period, 100)

    BackoffSampler.reset()
    BackoffSampler.trigger_next_cycle()

    # Target is 10, so it will sample the first 10
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()
    assert BackoffSampler.sample?()

    # The rest will be dropped
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()
    refute BackoffSampler.sample?()

    # Wait until the next cycle
    Process.sleep(110)

    # Next cycle it will adjust and take some, but not all
    decisions = [
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?(),
      BackoffSampler.sample?()
    ]

    assert true in decisions
    assert false in decisions
  end
end
