defmodule NewRelic.Telemetry.Plug do
  use GenServer

  @moduledoc """
  `Plug` based HTTP servers are auto-instrumented based on the `telemetry` integration
  built into `Plug.Cowboy` and `Plug`.

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

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @plug_start [:plug_cowboy, :stream_handler, :start]
  @plug_stop [:plug_cowboy, :stream_handler, :stop]
  @plug_exception [:plug_cowboy, :stream_handler, :exception]

  @plug_router_start [:plug, :router_dispatch, :start]

  @plug_events [
    @plug_start,
    @plug_stop,
    @plug_exception,
    @plug_router_start
  ]

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
  def handle_event(
        @plug_start,
        %{system_time: system_time},
        meta,
        _config
      ) do
    start_transaction(meta, system_time)
    start_distributed_trace(meta)
  end

  def handle_event(
        @plug_router_start,
        _measurements,
        %{conn: conn, route: route},
        _config
      ) do
    # Work around a race condition with spawn tracking:
    [connection_proc | _] = Process.get(:"$ancestors")
    Util.AttrStore.link(NewRelic.Transaction.Reporter, connection_proc, self())

    NewRelic.add_attributes(plug_name: plug_name(conn, route))
  end

  def handle_event(
        @plug_stop,
        %{duration: duration},
        meta,
        _config
      ) do
    stop_transaction(meta, duration)
    stop_distributed_trace(meta)
  end

  def handle_event(
        @plug_exception,
        %{duration: duration},
        %{kind: kind, reason: exit_reason},
        _config
      ) do
    {reason, stack} =
      case exit_reason do
        {{{reason, stack}, _init_call}, _exit_stack} -> {reason, stack}
        _other -> {:unknown, []}
      end

    error = %{kind: kind, reason: reason, stack: stack}
    conn = %{status: 500}

    stop_transaction(conn, error, duration)
    stop_distributed_trace(conn)
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp start_transaction(conn, system_time) do
    Transaction.Reporter.start()
    add_start_attrs(conn, system_time)
    maybe_report_queueing(conn)
  end

  defp start_distributed_trace(conn) do
    DistributedTrace.start(conn)
  end

  defp stop_transaction(conn, duration) do
    add_stop_attrs(conn, duration)
    Transaction.Reporter.complete(self(), :async)
  end

  defp stop_transaction(conn, error, duration) do
    add_stop_attrs(conn, duration)
    Transaction.Reporter.fail(error)
    Transaction.Reporter.complete(self(), :async)
  end

  defp stop_distributed_trace(_conn) do
    DistributedTrace.cleanup_context()
  end

  defp add_start_attrs(conn, system_time) do
    [
      system_time: system_time,
      host: conn.host,
      path: conn.request_path,
      remote_ip: conn.remote_ip |> :inet_parse.ntoa() |> to_string(),
      referer: Util.get_req_header(conn, "referer") |> List.first(),
      user_agent: Util.get_req_header(conn, "user-agent") |> List.first(),
      content_type: Util.get_req_header(conn, "content-type") |> List.first(),
      request_method: conn.method
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  defp add_stop_attrs(conn, duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      status: conn.status,
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions]
    ]
    |> NewRelic.add_attributes()
  end

  defp plug_name(conn, match_path),
    do:
      "/Plug/#{conn.method}/#{match_path}"
      |> String.replace("/*glob", "")
      |> String.replace("/*_path", "")

  @request_start_header "x-request-start"
  defp maybe_report_queueing(conn) do
    with [request_start | _] <- Util.get_req_header(conn, @request_start_header),
         {:ok, request_start_s} <- Util.RequestStart.parse(request_start) do
      NewRelic.add_attributes(request_start_s: request_start_s)
    else
      _ -> :ignore
    end
  end
end
