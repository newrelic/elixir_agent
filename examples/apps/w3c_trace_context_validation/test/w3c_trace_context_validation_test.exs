defmodule W3cTraceContextValidationTest do
  use ExUnit.Case

  test "greets the world" do
    assert {:ok, %{status_code: 404}} = HTTPoison.get("http://localhost:#{port()}/hello")
  end

  test "validator" do
    assert {:ok, %{status_code: 200}} =
             HTTPoison.post("http://localhost:#{port()}/test", "[]",
               "content-type": "application/json"
             )
  end

  def port() do
    Application.get_env(:w3c_trace_context_validation, :http_port)
  end
end
