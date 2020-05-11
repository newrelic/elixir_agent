defmodule NewRelic.Telemetry.Plug do
  use GenServer

  @moduledoc """
  `Plug` based HTTP servers are auto-instrumented based on the `telemetry` integration
  built into `Plug.Cowboy`.

  To prevent reporting the current transaction, call:
  ```elixir
  NewRelic.ignore_transaction()
  ```

  Inside a Transaction, the agent will track work across processes that are spawned as
  well as work done inside a Task Supervisor. When using `Task.Supervisor.async_nolink`
  you can signal to the agent not to track the work done inside the Task, which will
  exclude it from the current Transaction. To do this, send in an additional option:

  ```elixir
  Task.Supervisor.async_nolink(
    MyTaskSupervisor,
    fn -> do_work() end,
    new_relic: :no_track
  )
  ```
  """

  alias NewRelic.{Transaction, DistributedTrace, Util}

  # TODO: Should Telemetry GenServers only be started if NewRelic.Config.enabled?()

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @plug_start [:plug_adapter, :call, :start]
  @plug_stop [:plug_adapter, :call, :stop]
  @plug_exception [:plug_adapter, :call, :exception]

  @plug_events [@plug_start, @plug_stop, @plug_exception]

  @doc false
  def init(:ok) do
    config = %{
      handler_id: {:new_relic, :plug}
    }

    :telemetry.attach_many(
      config.handler_id,
      @plug_events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  @doc false
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(@plug_start, _measurements, %{conn: conn}, _config) do
    start_transaction(conn)
    start_distributed_trace(conn)
  end

  def handle_event(
        @plug_stop,
        %{duration: _duration},
        %{conn: conn},
        _config
      ) do
    # TODO: use duration
    stop_transaction(conn)
    stop_distributed_trace(conn)
  end

  def handle_event(
        @plug_exception,
        %{duration: _duration},
        %{conn: conn, kind: kind, reason: reason, stacktrace: stack},
        _config
      ) do
    # TODO: use duration
    conn = %{conn | status: 500}
    error = %{kind: kind, reason: reason, stack: stack}

    stop_transaction(conn, error)
    stop_distributed_trace(conn)
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp start_transaction(conn) do
    Transaction.Reporter.start()
    add_start_attrs(conn)
    maybe_report_queueing(conn)
  end

  defp start_distributed_trace(conn) do
    DistributedTrace.start(conn)
  end

  defp stop_transaction(conn) do
    add_stop_attrs(conn)
    Transaction.Reporter.complete(self(), :async)
  end

  defp stop_transaction(conn, error) do
    add_stop_attrs(conn)
    Transaction.Reporter.fail(error)
    Transaction.Reporter.complete(self(), :async)
  end

  defp stop_distributed_trace(_conn) do
    DistributedTrace.cleanup_context()
  end

  defp add_start_attrs(conn) do
    [
      host: conn.host,
      path: conn.request_path,
      remote_ip: conn.remote_ip |> :inet_parse.ntoa() |> to_string(),
      referer: Plug.Conn.get_req_header(conn, "referer") |> List.first(),
      user_agent: Plug.Conn.get_req_header(conn, "user-agent") |> List.first(),
      content_type: Plug.Conn.get_req_header(conn, "content-type") |> List.first(),
      request_method: conn.method
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  defp add_stop_attrs(conn) do
    info = Process.info(self(), [:memory, :reductions])

    [
      plug_name: plug_name(conn),
      status: conn.status,
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions]
    ]
    |> NewRelic.add_attributes()
  end

  defp plug_name(conn),
    do:
      "/Plug/#{conn.method}/#{match_path(conn)}"
      |> String.replace("/*glob", "")
      |> String.replace("/*_path", "")

  defp match_path(conn) do
    case conn.private[:plug_route] do
      {match_path, _fun} -> match_path
      _ -> nil
    end
  end

  @request_start_header "x-request-start"
  defp maybe_report_queueing(conn) do
    with [request_start | _] <- Plug.Conn.get_req_header(conn, @request_start_header),
         {:ok, request_start_s} <- Util.RequestStart.parse(request_start) do
      NewRelic.add_attributes(request_start_s: request_start_s)
    else
      _ -> :ignore
    end
  end
end