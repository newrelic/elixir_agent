defmodule NewRelic.Telemetry.Tesla do
  use GenServer

  @tesla_request_stop [:tesla, :request, :stop]

  def start_link() do
    enabled = NewRelic.Config.feature?(:tesla_instrumentation)
    GenServer.start_link(__MODULE__, [enabled: enabled], name: __MODULE__)
  end

  def init(enabled: false), do: :ignore

  def init(enabled: true) do
    config = %{
      handler_id: {:new_relic, :tesla}
    }

    :telemetry.attach_many(
      config.handler_id,
      [@tesla_request_stop],
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(
        @tesla_request_stop = _event,
        %{duration: duration} = _measurements,
        %{env: env} = _metadata,
        _config
      ) do
    end_time_ms = System.system_time(:millisecond)
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    duration_s = duration_ms / 1000
    start_time_ms = end_time_ms - duration_ms

    method = String.upcase(to_string(env.method))
    url = env.url
    status = env.status
    %{host: host} = URI.parse(url)

    pid = inspect(self())
    id = {:tesla, make_ref()}
    parent_id = Process.get(:nr_current_span) || :root

    metric_name = "External/#{host}/Tesla/#{method}"

    NewRelic.Transaction.Reporter.add_trace_segment(%{
      name: metric_name,
      attributes: %{
        "http.method": method,
        "http.url": url,
        "http.status": status
      },
      pid: pid,
      id: id,
      parent_id: parent_id,
      start_time: start_time_ms,
      end_time: end_time_ms
    })

    NewRelic.report_span(
      timestamp_ms: start_time_ms,
      duration_s: duration_s,
      name: metric_name,
      edge: [span: id, parent: parent_id],
      category: "http",
      attributes: %{
        component: "Tesla",
        "http.method": method,
        "http.url": url,
        "http.status": status
      }
    )

    NewRelic.report_metric({:external, host, "Tesla", method}, duration_s: duration_s)

    NewRelic.Transaction.Reporter.track_metric({:external, duration_s})

    NewRelic.incr_attributes(
      external_call_count: 1,
      external_duration_ms: duration_ms,
      "external.#{host}.call_count": 1,
      "external.#{host}.duration_ms": duration_ms
    )
  end
end
