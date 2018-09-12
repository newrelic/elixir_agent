defmodule InstrumentedTest do
  use ExUnit.Case

  setup_all do
    Application.ensure_all_started(:httpoison)
    :ok
  end

  test "HTTPoison" do
    {:ok, response} = NewRelic.Instrumented.HTTPoison.get("http://www.google.com")
    assert response.status_code == 200
  end

  test "HTTPoison request" do
    {:ok, response} = NewRelic.Instrumented.HTTPoison.request(:get, "http://www.google.com")
    assert response.status_code == 200
  end
end
