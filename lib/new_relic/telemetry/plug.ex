defmodule NewRelic.Telemetry.Plug do
  use GenServer

  @moduledoc """
  Provides `Plug` instrumentation via `telemetry`.

  Plug pipelines are auto-discovered and instrumented.

  We automatically gather:

  * Transaction metrics and events
  * Transaction Traces
  * Distributed Traces

  You can opt-out of this instrumentation via configuration. See `NewRelic.Config` for details.

  ----

  To prevent reporting an individual transaction:

  ```elixir
  NewRelic.ignore_transaction()
  ```

  ----

  Inside a Transaction, the agent will track work across processes that are spawned and linked.
  You can signal to the agent not to track work done inside a spawned process, which will
  exclude it from the current Transaction.

  To exclude a process from the Transaction:

  ```elixir
  Task.async(fn ->
    NewRelic.exclude_from_transaction()
    Work.wont_be_tracked()
  end)
  ```
  """

  alias NewRelic.{Transaction, DistributedTrace, Util}

  @doc false
  def start_link(_) do
    config = %{
      enabled?: NewRelic.Config.feature?(:plug_instrumentation),
      handler_id: {:new_relic, :plug}
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
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
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
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
    Transaction.Reporter.start_transaction(:web)

    if NewRelic.Config.enabled?(),
      do: DistributedTrace.start(:http, meta.req.headers)

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
        %{duration: duration} = meas,
        meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)
    add_stop_error_attrs(meta)

    Transaction.Reporter.stop_transaction(:web)
  end

  # Don't treat 404 as an exception
  def handle_event(
        @cowboy_exception,
        %{duration: duration} = meas,
        %{resp_status: "404" <> _} = meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)

    Transaction.Reporter.stop_transaction(:web)
  end

  def handle_event(
        @cowboy_exception,
        %{duration: duration} = meas,
        %{kind: kind} = meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)
    {reason, stack} = reason_and_stack(meta)

    Transaction.Reporter.fail(%{kind: kind, reason: reason, stack: stack})
    Transaction.Reporter.stop_transaction(:web)
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
  defp add_stop_attrs(meas, meta, duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      status: status_code(meta),
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions],
      "cowboy.req_body_duration_ms": meas[:req_body_duration] |> to_ms,
      "cowboy.resp_duration_ms": meas[:resp_duration] |> to_ms,
      "cowboy.req_body_length": meas[:req_body_length],
      "cowboy.resp_body_length": meas[:resp_body_length]
    ]
    |> NewRelic.add_attributes()
  end

  defp add_stop_error_attrs(%{resp_status: "5" <> _, error: {:socket_error, error, message}}) do
    [
      error: true,
      "cowboy.socket_error": error,
      "cowboy.socket_error.message": message
    ]
    |> NewRelic.add_attributes()
  end

  # client timeout:
  defp add_stop_error_attrs(%{error: {:socket_error, error, message}}) do
    [
      "cowboy.socket_error": error,
      "cowboy.socket_error.message": message
    ]
    |> NewRelic.add_attributes()
  end

  # server timeout:
  defp add_stop_error_attrs(%{error: {:connection_error, error, message}}) do
    [
      "cowboy.connection_error": error,
      "cowboy.connection_error.message": message
    ]
    |> NewRelic.add_attributes()
  end

  defp add_stop_error_attrs(_meta) do
    :ok
  end

  defp to_ms(duration),
    do: System.convert_time_unit(duration, :native, :microsecond) / 1000

  @request_start_header "x-request-start"
  defp maybe_report_queueing(meta) do
    with true <- NewRelic.Config.feature?(:request_queuing_metrics),
         request_start when is_binary(request_start) <- meta.req.headers[@request_start_header],
         {:ok, request_start_s} <- Util.RequestStart.parse(request_start) do
      NewRelic.add_attributes(request_start_s: request_start_s)
    end
  end

  defp status_code(%{resp_status: :undefined}) do
    nil
  end

  defp status_code(%{resp_status: status})
       when is_integer(status) do
    status
  end

  defp status_code(%{resp_status: status})
       when is_binary(status) do
    String.split(status) |> List.first() |> String.to_integer()
  end

  defp reason_and_stack(%{reason: %{__exception__: true} = reason, stacktrace: stack}) do
    {reason, stack}
  end

  defp reason_and_stack(%{reason: {{reason, stack}, _init_call}}) do
    {reason, stack}
  end

  defp reason_and_stack(%{reason: {reason, _init_call}}) do
    {reason, []}
  end

  defp reason_and_stack(unexpected_cowboy_exception) do
    NewRelic.log(:debug, "unexpected_cowboy_exception: #{inspect(unexpected_cowboy_exception)}")
    {:unexpected_cowboy_exception, []}
  end

  defp plug_name(conn, match_path) do
    "/Plug/#{conn.method}/#{match_path}"
    |> String.replace("/*glob", "")
    |> String.replace("/*_path", "")
  end
end
