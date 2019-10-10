defmodule UtilRequestQueueTimeTest do
  alias Util.RequestQueueTime

  use ExUnit.Case, async: true

  describe "parse x-request-start header" do
    test "handles t={microseconds} formatted strings" do
      now_us = System.system_time(:microsecond)
      assert RequestQueueTime.parse("t=#{now_us}") == {:ok, now_us / 1_000_000}
    end

    test "handles t={microseconds}.0 formatted strings" do
      now_us = System.system_time(:microsecond)
      assert RequestQueueTime.parse("t=#{now_us}.0") == {:ok, now_us / 1_000_000}
    end

    test "handles t={milliseconds} formatted strings" do
      now_ms = System.system_time(:millisecond)
      assert RequestQueueTime.parse("t=#{now_ms}") == {:ok, now_ms / 1000}
    end

    test "handles t={seconds} formatted strings" do
      now_s = System.system_time(:second)
      assert RequestQueueTime.parse("t=#{now_s}") == {:ok, now_s}
    end

    test "handles t={fractional seconds} formatted strings" do
      now_us = System.system_time(:microsecond)
      assert RequestQueueTime.parse("t=#{now_us / 1_000_000}") == {:ok, now_us / 1_000_000}
    end

    test "handles t={s in the future} formatted strings" do
      now_s = System.system_time(:second)
      assert {:ok, time} = RequestQueueTime.parse("t=#{now_s + 10}")
      assert_in_delta time, now_s, 11
    end

    test "an invalid format is an error" do
      assert RequestQueueTime.parse("nope") == :error
    end

    test "an early time is an error" do
      assert RequestQueueTime.parse("t=1") == :error
    end
  end
end
