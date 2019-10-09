defmodule NewRelic.Transaction.Plug do
  @behaviour Plug
  import Plug.Conn
  require Logger

  # This Plug wires up Transaction reporting
  #  - `on_call` is triggered at the beginning of the request
  #  - `before_send` is triggered at the end, and reports the data to the Transaction.Reporter

  @moduledoc false

  alias NewRelic.Transaction
  alias NewRelic.Transaction.RequestQueueTime

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{private: %{newrelic_tx_instrumented: true}} = conn, _opts) do
    Logger.warn(
      "You have instrumented twice in the same plug! Please `use NewRelic.Transaction` only once."
    )

    conn
  end

  def call(conn, _opts) do
    conn
    |> on_call
    |> put_private(:newrelic_tx_instrumented, true)
    |> register_before_send(&before_send/1)
  end

  defp on_call(conn) do
    Transaction.Reporter.start()
    add_start_attrs(conn)
    maybe_report_queueing(conn)
    conn
  end

  defp before_send(conn) do
    add_stop_attrs(conn)
    Transaction.Reporter.complete()
    conn
  end

  def add_start_attrs(conn) do
    [
      host: conn.host,
      path: conn.request_path,
      remote_ip: conn.remote_ip |> :inet_parse.ntoa() |> to_string(),
      referer: get_req_header(conn, "referer") |> List.first(),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      content_type: get_req_header(conn, "content-type") |> List.first(),
      request_method: conn.method
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  def add_stop_attrs(conn) do
    info = Process.info(self(), [:memory, :reductions])

    [
      plug_name: plug_name(conn),
      status: conn.status,
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions]
    ]
    |> NewRelic.add_attributes()
  end

  def plug_name(conn),
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

  defp maybe_report_queueing(conn) do
    [
      queue_start_us: extract_queue_start_us(conn)
    ]
    |> NewRelic.add_attributes()
  end

  @queue_duration_headers ["x-request-start", "x-queue-start", "x-middleware-start"]

  defp extract_queue_start_us(%{req_headers: headers}),
    do:
      Enum.reduce_while(headers, nil, fn
        {header, timestamp}, acc when header in @queue_duration_headers ->
          case RequestQueueTime.timestamp_to_us(timestamp) do
            {:ok, us} ->
              {:halt, us}

            {:error, reason} ->
              Logger.debug(reason)
              {:cont, acc}
          end

        _, acc ->
          {:cont, acc}
      end)
end
