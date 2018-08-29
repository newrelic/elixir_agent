defmodule NewRelic.Transaction.Plug do
  import Plug.Conn
  alias NewRelic.Transaction
  require Logger

  # This Plug wires up Transaction reporting
  #  - `on_call` is triggered at the beginning of the request
  #  - `before_send` is triggered at the end, and reports the data to the Transaction.Reporter

  @moduledoc false

  def init(opts), do: opts

  def call(%{private: %{newrelic_instrumented: true}} = conn, _opts) do
    Logger.warn(
      "You have instrumented twice in the same plug! Please `use NewRelic.Transaction` only once."
    )

    conn
  end

  def call(conn, _opts) do
    conn
    |> on_call
    |> register_before_send(&before_send/1)
    |> put_private(:newrelic_instrumented, true)
  end

  defp on_call(conn) do
    Transaction.Reporter.start()
    add_start_attrs(conn)
    conn
  end

  defp before_send(conn) do
    add_stop_attrs(conn)
    Transaction.Reporter.stop(conn)
    conn
  end

  def add_start_attrs(conn) do
    [
      host: conn.host,
      path: conn.request_path,
      remote_ip: conn.remote_ip |> :inet_parse.ntoa() |> to_string(),
      referer: get_req_header(conn, "referer") |> List.first(),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      request_method: conn.method
    ]
    |> NewRelic.add_attributes()
  end

  def add_stop_attrs(conn) do
    [
      default_name: default_name(conn),
      status: conn.status
    ]
    |> NewRelic.add_attributes()
  end

  def default_name(conn),
    do:
      "/Plug/#{conn.method}/#{match_path(conn)}"
      |> String.replace("/*glob", "")
      |> String.replace("/*_path", "")

  def match_path(conn) do
    case conn.private[:plug_route] do
      {match_path, _fun} -> match_path
      _ -> nil
    end
  end
end
