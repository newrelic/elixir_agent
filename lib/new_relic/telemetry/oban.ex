defmodule NewRelic.Telemetry.Oban do
  use GenServer

  @moduledoc """
  Provides `Oban` instrumentation via `telemetry`.

  Oban jobs are auto-discovered and instrumented.

  We automatically gather:

  * Transaction metrics and events
  * Transaction Traces
  * Distributed Traces

  You can opt-out of this instrumentation with `:oban_instrumentation_enabled` via configuration.
  See `NewRelic.Config` for details.
  """

  alias NewRelic.Transaction

  @doc false
  def start_link(_) do
    config = %{
      enabled?: NewRelic.Config.feature?(:oban_instrumentation),
      handler_id: {:new_relic, :oban}
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @oban_start [:oban, :job, :start]
  @oban_stop [:oban, :job, :stop]
  @oban_exception [:oban, :job, :exception]

  @oban_events [
    @oban_start,
    @oban_stop,
    @oban_exception
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach_many(
      config.handler_id,
      @oban_events,
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
        @oban_start,
        %{system_time: start_time},
        meta,
        _config
      ) do
    Transaction.Reporter.start_transaction(:other)
    NewRelic.DistributedTrace.start(:other)

    add_start_attrs(meta, start_time)
  end

  def handle_event(
        @oban_stop,
        %{duration: duration} = meas,
        meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)

    Transaction.Reporter.stop_transaction(:other)
  end

  def handle_event(
        @oban_exception,
        %{duration: duration} = meas,
        meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)

    if NewRelic.Config.feature?(:error_collector) do
      Transaction.Reporter.error(%{kind: meta.kind, reason: meta.reason, stack: meta.stacktrace})
    else
      NewRelic.add_attributes(error: true)
    end

    Transaction.Reporter.stop_transaction(:other)
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp add_start_attrs(meta, start_time) do
    [
      pid: inspect(self()),
      start_time: start_time,
      other_transaction_name: "Oban/#{meta.queue}/#{meta.worker}/perform",
      "oban.worker": meta.worker,
      "oban.queue": meta.queue,
      "oban.job.args": meta.job.args,
      "oban.job.tags": meta.job.tags |> Enum.join(","),
      "oban.job.attempt": meta.job.attempt,
      "oban.job.attempted_by": meta.job.attempted_by |> Enum.join("."),
      "oban.job.max_attempts": meta.job.max_attempts,
      "oban.job.priority": meta.job.priority
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  defp add_stop_attrs(meas, meta, duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions],
      "oban.job.result": meta.state,
      "oban.job.queue_time": System.convert_time_unit(meas.queue_time, :native, :microsecond) / 1000
    ]
    |> NewRelic.add_attributes()
  end
end
