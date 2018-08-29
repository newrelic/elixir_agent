defmodule BackoffSamplerTest do
  use ExUnit.Case
  alias NewRelic.DistributedTrace.BackoffSampler

  test "Backoff behavior as best as we can" do
    send(BackoffSampler, :reset)

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

    send(BackoffSampler, :cycle)

    decisions = [
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
end
