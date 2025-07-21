defmodule NewRelic.Telemetry.Finch do
  use GenServer
  require Logger

  @moduledoc """
  Provides `Finch` instrumentation via `telemetry`.

  Finch requests are auto-discovered and instrumented as "external" calls.

  We automatically gather:
  * Transaction segments
  * External metrics
  * External spans

  You can opt-out of this instrumentation with `:finch_instrumentation_enabled` via configuration.
  See `NewRelic.Config` for details.
  """
  def start_link(_) do
    config = %{
      enabled?: NewRelic.Config.feature?(:finch_instrumentation),
      handler_id: {:new_relic, :finch}
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @finch_request_start [:finch, :request, :start]
  @finch_request_stop [:finch, :request, :stop]
  @finch_request_exception [:finch, :request, :exception]

  @finch_events [
    @finch_request_start,
    @finch_request_stop,
    @finch_request_exception
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach_many(
      config.handler_id,
      @finch_events,
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

  def handle_event(
        @finch_request_start,
        %{system_time: start_time},
        %{request: request},
        config
      ) do
    if instrument?() do
      {span, previous_span, previous_span_attrs} =
        NewRelic.DistributedTrace.set_current_span(
          label: {request.method, request.scheme, request.host, request.path},
          ref: make_ref()
        )

      Process.put(
        config.handler_id,
        %{
          start_time: start_time,
          span: span,
          previous_span: previous_span,
          previous_span_attrs: previous_span_attrs
        }
      )
    end
  end

  def handle_event(
        @finch_request_stop,
        %{duration: duration},
        %{name: finch_pool, request: request, result: result},
        config
      ) do
    if instrument?() do
      with %{
             start_time: start_time,
             span: span,
             previous_span: previous_span,
             previous_span_attrs: previous_span_attrs
           } <- Process.delete(config.handler_id) do
        metric_name = "External/#{request.host}/Finch/#{request.method}"
        secondary_name = "#{request.host} - Finch/#{request.method}"

        duration_ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
        duration_s = duration_ms / 1000

        id = span
        parent_id = previous_span || :root

        url =
          URI.to_string(%URI{scheme: "#{request.scheme}", host: request.host, path: request.path})

        result_attrs =
          case result do
            {:ok, %{__struct__: Finch.Response} = response} -> %{"response.status": response.status}
            {:ok, _acc} -> %{}
            {:error, exception} -> %{error: true, "error.message": Exception.message(exception)}
            {:error, exception, _req} -> %{error: true, "error.message": Exception.message(exception)}
          end

        NewRelic.Transaction.Reporter.add_trace_segment(%{
          primary_name: metric_name,
          secondary_name: secondary_name,
          attributes: %{},
          pid: self(),
          id: span,
          parent_id: parent_id,
          start_time: start_time,
          duration: duration
        })

        NewRelic.report_span(
          timestamp_ms: System.convert_time_unit(start_time, :native, :millisecond),
          duration_s: duration_s,
          name: metric_name,
          edge: [span: id, parent: parent_id],
          category: "http",
          attributes:
            %{
              url: url,
              method: request.method,
              component: "Finch",
              "finch.pool": finch_pool
            }
            |> Map.merge(result_attrs)
        )

        NewRelic.incr_attributes(
          "external.#{request.host}.call_count": 1,
          "external.#{request.host}.duration_ms": duration_ms
        )

        NewRelic.report_metric(
          {:external, url, "Finch", request.method},
          duration_s: duration_s
        )

        NewRelic.Transaction.Reporter.track_metric({
          {:external, url, "Finch", request.method},
          duration_s: duration_s
        })

        NewRelic.DistributedTrace.reset_span(
          previous_span: previous_span,
          previous_span_attrs: previous_span_attrs
        )
      end
    end
  end

  def handle_event(
        @finch_request_exception,
        %{duration: duration},
        %{kind: kind, reason: reason, name: finch_pool, request: request},
        config
      ) do
    if instrument?() do
      with %{
             start_time: start_time,
             span: span,
             previous_span: previous_span,
             previous_span_attrs: previous_span_attrs
           } <- Process.delete(config.handler_id) do
        metric_name = "External/#{request.host}/Finch/#{request.method}"

        duration_ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
        duration_s = duration_ms / 1000

        id = span
        parent_id = previous_span || :root

        url = URI.to_string(%URI{scheme: "#{request.scheme}", host: request.host, path: request.path})

        error_message = NewRelic.Util.Error.format_reason(kind, reason)

        NewRelic.report_span(
          timestamp_ms: System.convert_time_unit(start_time, :native, :millisecond),
          duration_s: duration_s,
          name: metric_name,
          edge: [span: id, parent: parent_id],
          category: "http",
          attributes: %{
            url: url,
            method: request.method,
            component: "Finch",
            "finch.pool": finch_pool,
            error: true,
            "error.message": error_message
          }
        )

        NewRelic.DistributedTrace.reset_span(
          previous_span: previous_span,
          previous_span_attrs: previous_span_attrs
        )
      end
    end
  end

  def handle_event(_event, _measurements, _meta, config) do
    with %{
           previous_span: previous_span,
           previous_span_attrs: previous_span_attrs
         } <- Process.delete(config.handler_id) do
      NewRelic.DistributedTrace.reset_span(
        previous_span: previous_span,
        previous_span_attrs: previous_span_attrs
      )
    end
  end

  # Avoid double instrumenting in situation where
  # application has manually instrumented externals already
  defp instrument?() do
    case Process.get(:nr_already_tracing_external) do
      true ->
        warn_once(
          "[New Relic] Trace `:external` deprecated in favor of automatic Finch instrumentation. " <>
            "Please remove @trace `category: :external` annotations from Finch requests, or disable " <>
            "automatic Finch instrumentation."
        )

        false

      _ ->
        true
    end
  end

  defp warn_once(message) do
    case :persistent_term.get(__MODULE__, :not_logged) do
      :logged ->
        :skip

      :not_logged ->
        :persistent_term.put(__MODULE__, :logged)
        Logger.warning(message)
    end
  end
end
