defmodule InstrumentedTest do
  use ExUnit.Case

  setup_all do
    Application.ensure_all_started(:httpoison)
    :ok
  end

  alias NewRelic.Instrumented.HTTPoison

  test "HTTPoison" do
    {:ok, response} = HTTPoison.get("http://www.google.com")
    assert response.status_code == 200
  end

  test "HTTPoison request" do
    {:ok, response} = HTTPoison.request(:get, "http://www.google.com")
    assert response.status_code == 200
  end

  test "original HTTPoison.Error struct is returned" do
    {:error, %Elixir.HTTPoison.Error{}} = HTTPoison.get("localhost:12345")
  end
end
