defmodule NewRelic.Transaction.RequestQueueTimeTest do
  alias NewRelic.Transaction.RequestQueueTime

  use ExUnit.Case, async: true

  describe "timestamp_to_us/1" do
    test "handles t={microseconds} formatted strings" do
      now_us = System.system_time(:microsecond)
      assert RequestQueueTime.timestamp_to_us("t=#{now_us}") == {:ok, now_us}
    end

    test "handles t={microseconds}.0 formatted strings" do
      now_us = System.system_time(:microsecond)
      assert RequestQueueTime.timestamp_to_us("t=#{now_us}.0") == {:ok, now_us}
    end

    test "handles t={milliseconds} formatted strings" do
      now_ms = System.system_time(:millisecond)
      assert RequestQueueTime.timestamp_to_us("t=#{now_ms}") == {:ok, now_ms * 1_000}
    end

    test "handles t={seconds} formatted strings" do
      now_s = System.system_time(:second)
      assert RequestQueueTime.timestamp_to_us("t=#{now_s}") == {:ok, now_s * 1_000_000}
    end

    test "handles t={fractional seconds} formatted strings" do
      now_us = System.system_time(:microsecond)
      assert RequestQueueTime.timestamp_to_us("t=#{now_us / 1_000_000}") == {:ok, now_us}
    end

    test "handles t={s in the future} formatted strings" do
      now_s = System.system_time(:second)
      assert {:ok, time} = RequestQueueTime.timestamp_to_us("t=#{now_s + 10}")
      assert_in_delta time, now_s * 1_000_000, 1_000_000
    end

    test "an invalid format is an error" do
      assert RequestQueueTime.timestamp_to_us("nope") ==
               {:error, "invalid request queueing format, expected `t=\d+`"}
    end

    test "an early time is an error" do
      assert RequestQueueTime.timestamp_to_us("t=1") == {:error, "timestamp '1' is not valid"}
    end
  end
end
