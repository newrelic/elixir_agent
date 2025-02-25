defmodule NewRelic.Telemetry.PhoenixLiveView do
  use GenServer

  alias NewRelic.Transaction
  alias NewRelic.Tracer

  @moduledoc """
  Provides Phoenix `LiveView` instrumentation via `telemetry`.

  This instrumentation collects Transactions for the initial LiveView lifecycle events
  that occur inside the WebSocket process, as well as metrics for subsequent instances
  of lifecycle events.

  You can opt-out of this instrumentation as a whole with `:phoenix_live_view_instrumentation_enabled`,
  and specifically out of params collection with `:function_argument_collection_enabled` via configuration.

  See `NewRelic.Config` for details.
  """
  def start_link(_) do
    config = %{
      handler_id: {:new_relic, :phoenix_live_view},
      enabled?: NewRelic.Config.feature?(:phoenix_live_view_instrumentation),
      collect_args?: NewRelic.Config.feature?(:function_argument_collection)
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @live_view_mount_start [:phoenix, :live_view, :mount, :start]
  @live_view_mount_stop [:phoenix, :live_view, :mount, :stop]
  @live_view_mount_exception [:phoenix, :live_view, :mount, :exception]

  @live_view_handle_params_start [:phoenix, :live_view, :handle_params, :start]
  @live_view_handle_params_stop [:phoenix, :live_view, :handle_params, :stop]
  @live_view_handle_params_exception [:phoenix, :live_view, :handle_params, :exception]

  @live_view_handle_event_start [:phoenix, :live_view, :handle_event, :start]
  @live_view_handle_event_stop [:phoenix, :live_view, :handle_event, :stop]
  @live_view_handle_event_exception [:phoenix, :live_view, :handle_event, :exception]

  @live_view_render_start [:phoenix, :live_view, :render, :start]
  @live_view_render_stop [:phoenix, :live_view, :render, :stop]
  @live_view_render_exception [:phoenix, :live_view, :render, :exception]

  @live_view_events [
    @live_view_mount_start,
    @live_view_mount_stop,
    @live_view_mount_exception,
    @live_view_handle_params_start,
    @live_view_handle_params_stop,
    @live_view_handle_params_exception,
    @live_view_handle_event_start,
    @live_view_handle_event_stop,
    @live_view_handle_event_exception,
    @live_view_render_start,
    @live_view_render_stop,
    @live_view_render_exception
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach_many(
      config.handler_id,
      @live_view_events,
      &__MODULE__.handle_event/4,
      config
    )

    {:ok, config}
  end

  @doc false
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(@live_view_mount_start, meas, meta, config) do
    if meta.socket.transport_pid do
      {host, path} = parse_uri(meta.uri)

      # We're in the LiveView WebSocket process, collect a Transaction
      with :collect <- Transaction.Reporter.start_transaction(:web, path) do
        NewRelic.DistributedTrace.start(:other)
        framework_name = "/Phoenix.LiveView/Live/#{inspect(meta.socket.view)}/#{meta.socket.assigns.live_action}"

        NewRelic.add_attributes(
          pid: inspect(self()),
          start_time: meas.system_time,
          framework_name: framework_name,
          host: host,
          path: path,
          "live_view.router": inspect(meta.socket.router),
          "live_view.endpoint": inspect(meta.socket.endpoint),
          "live_view.action": meta.socket.assigns[:live_action],
          "live_view.socket_id": meta.socket.id
        )
      end
    end

    Tracer.Direct.start_span(
      meta.telemetry_span_context,
      "#{inspect(meta.socket.view)}:#{meta.socket.assigns.live_action}.mount",
      system_time: meas.system_time,
      attributes: [
        "live_view.params": config.collect_args? && meta[:params] && inspect(meta[:params])
      ]
    )
  end

  def handle_event([_, _, type, _] = event, meas, meta, config)
      when event in [
             @live_view_handle_params_start,
             @live_view_handle_event_start,
             @live_view_render_start
           ] do
    Tracer.Direct.start_span(
      meta.telemetry_span_context,
      "#{inspect(meta.socket.view)}:#{meta.socket.assigns.live_action}.#{type}",
      system_time: meas.system_time,
      attributes: [
        event: meta[:event],
        params: config.collect_args? && meta[:params] && inspect(meta[:params]),
        "live_view.render.changed?": meta[:changed?],
        "live_view.render.force?": meta[:force?]
      ]
    )
  end

  def handle_event(event, meas, meta, _config)
      when event in [
             @live_view_mount_stop,
             @live_view_handle_params_stop,
             @live_view_handle_event_stop
           ] do
    Tracer.Direct.stop_span(meta.telemetry_span_context, duration: meas.duration)
  end

  def handle_event(event, meas, meta, _config)
      when event in [
             @live_view_mount_exception,
             @live_view_handle_params_exception,
             @live_view_handle_event_exception
           ] do
    Tracer.Direct.stop_span(
      meta.telemetry_span_context,
      duration: meas.duration,
      attributes: [error: true, "error.kind": meta.kind, "error.reason": inspect(meta.reason)]
    )
  end

  def handle_event(@live_view_render_stop, meas, meta, _config) do
    Tracer.Direct.stop_span(meta.telemetry_span_context, duration: meas.duration)

    if meta.socket.transport_pid do
      Transaction.Reporter.stop_transaction(:web)
    end
  end

  def handle_event(@live_view_render_exception, meas, meta, _config) do
    Tracer.Direct.stop_span(
      meta.telemetry_span_context,
      duration: meas.duration,
      attributes: [error: true, "error.kind": meta.kind, "error.reason": inspect(meta.reason)]
    )

    if meta.socket.transport_pid do
      Transaction.Reporter.stop_transaction(:web)
    end
  end

  def handle_event(_event, _meas, _meta, _config) do
    :ignore
  end

  defp parse_uri(nil),
    do: {"unknown", "unknown"}

  defp parse_uri(uri) do
    uri = URI.parse(uri)
    {uri.host, uri.path}
  end
end
