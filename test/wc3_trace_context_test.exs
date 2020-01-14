defmodule W3CTraceContextTest do
  use ExUnit.Case

  alias NewRelic.W3CTraceContext.TraceParent
  alias NewRelic.W3CTraceContext.TraceState

  test "decode traceparent header" do
    assert_invalid(TraceParent, "00-00000000000000000000000000000000-00000000000000ea-01")
    assert_invalid(TraceParent, "00-000000000000000000000000000000AA-0000000000000000-01")
    assert_invalid(TraceParent, "asdf")

    assert_valid(TraceParent, "00-000000000000000000000000000000AA-00000000000000ea-01")
    assert_valid(TraceParent, "00-000000000000000000000000000000AA-00000000000000ea-00")
  end

  test "parse tracestate" do
    assert_valid(
      TraceState,
      "190@nr=0-0-709288-8599547-f85f42fd82a4cf1d-164d3b4b0d09cb05-1-0.789-1563574856827,@vendor=value"
    )
  end

  def assert_valid(module, header) do
    assert String.downcase(header) ==
             header
             |> module.decode()
             |> module.encode()
  end

  def assert_invalid(module, header) do
    assert :invalid == module.decode(header)
  end
end
