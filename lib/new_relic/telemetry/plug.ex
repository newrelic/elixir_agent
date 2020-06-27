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
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @cowboy_start [:cowboy, :request, :start]
  @cowboy_stop [:cowboy, :request, :stop]
  @cowboy_exception [:cowboy, :request, :exception]

  @plug_router_start [:plug, :router_dispatch, :start]

  @plug_events [
    @cowboy_start,
    @cowboy_stop,
    @cowboy_exception,
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
        @cowboy_start,
        %{system_time: system_time},
        meta,
        _config
      ) do
    Transaction.Reporter.start()
    DistributedTrace.start(:http, meta.req.headers)

    add_start_attrs(meta, system_time)
    maybe_report_queueing(meta)
  end

  def handle_event(
        @plug_router_start,
        _measurements,
        %{conn: conn, route: route},
        _config
      ) do
    NewRelic.add_attributes(plug_name: plug_name(conn, route))
  end

  def handle_event(
        @cowboy_stop,
        %{duration: duration},
        meta,
        _config
      ) do
    add_stop_attrs(meta, duration)
    Transaction.Reporter.stop()
  end

  def handle_event(
        @cowboy_exception,
        %{duration: duration},
        %{kind: kind, reason: exception_reason} = meta,
        _config
      ) do
    add_stop_attrs(meta, duration)

    {reason, stack} = error_reason(exception_reason)
    Transaction.Reporter.fail(%{kind: kind, reason: reason, stack: stack})
    Transaction.Reporter.stop()
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp add_start_attrs(meta, system_time) do
    [
      pid: inspect(self()),
      system_time: system_time,
      host: meta.req.host,
      path: meta.req.path,
      remote_ip: meta.req.peer |> elem(0) |> :inet_parse.ntoa() |> to_string(),
      referer: meta.req.headers["referer"],
      user_agent: meta.req.headers["user-agent"],
      content_type: meta.req.headers["content-type"],
      request_method: meta.req.method
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  defp add_stop_attrs(meta, duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      status: status_code(meta),
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions]
    ]
    |> NewRelic.add_attributes()
  end

  defp status_code(%{response: {:response, status, _, _}}),
    do: String.split(status) |> List.first() |> String.to_integer()

  defp status_code(%{error_response: {:error_response, status, _, _}}),
    do: status

  defp status_code(_), do: nil

  defp error_reason({{{reason, stack}, _init_call}, _exit_stack}), do: {reason, stack}
  defp error_reason(reason), do: {reason, []}

  defp plug_name(conn, match_path),
    do:
      "/Plug/#{conn.method}/#{match_path}"
      |> String.replace("/*glob", "")
      |> String.replace("/*_path", "")

  @request_start_header "x-request-start"
  defp maybe_report_queueing(meta) do
    with request_start when is_binary(request_start) <- meta.req.headers[@request_start_header],
         {:ok, request_start_s} <- Util.RequestStart.parse(request_start) do
      NewRelic.add_attributes(request_start_s: request_start_s)
    else
      _ -> :ignore
    end
  end
end
