defmodule LoggerTest do
  use ExUnit.Case

  test "memory Logger" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :memory})

    try do
      NewRelic.log(:warning, "OH_NO!")

      log = GenServer.call(NewRelic.Logger, :flush)
      assert log =~ "[WARN]"
      assert log =~ "OH_NO"
    after
      GenServer.call(NewRelic.Logger, {:replace, previous_logger})
    end
  end

  test "file Logger" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, {:file, "tmp/test.log"}})

    try do
      NewRelic.log(:error, "OH_NO!")

      :timer.sleep(100)
      log = File.read!("tmp/test.log")
      assert log =~ "[ERROR]"
      assert log =~ "OH_NO"
    after
      File.rm!("tmp/test.log")
      GenServer.call(NewRelic.Logger, {:replace, previous_logger})
    end
  end

  @tag :capture_log
  test "Logger logger" do
    previous_logger = GenServer.call(NewRelic.Logger, {:logger, :logger})
    NewRelic.log(:info, "HELLO")
    NewRelic.log(:error, "DANG")
    GenServer.call(NewRelic.Logger, {:replace, previous_logger})
  end
end
