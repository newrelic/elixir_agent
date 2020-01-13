defmodule W3CTraceContextTest do
  use ExUnit.Case

  alias NewRelic.W3CTraceContext.TraceParent

  test "decode traceparent header" do
    assert_invalid("00-00000000000000000000000000000000-00000000000000ea-01")
    assert_invalid("00-000000000000000000000000000000AA-0000000000000000-01")
    assert_invalid("asdf")

    assert_valid("00-000000000000000000000000000000AA-00000000000000ea-01")
    assert_valid("00-000000000000000000000000000000AA-00000000000000ea-00")
  end

  def assert_valid(header) do
    assert header |> String.downcase() ==
             header
             |> TraceParent.decode()
             |> IO.inspect()
             |> TraceParent.encode()
  end

  def assert_invalid(header) do
    assert :invalid == TraceParent.decode(header)
  end
end
