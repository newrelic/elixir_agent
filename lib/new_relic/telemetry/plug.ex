defmodule NewRelic.Telemetry.Plug do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @plug_start [:plug_adapter, :call, :start]
  @plug_stop [:plug_adapter, :call, :stop]
  @plug_exception [:plug_adapter, :call, :exception]

  @plug_events [@plug_start, @plug_stop, @plug_exception]

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

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(@plug_start, _measurements, %{conn: conn}, _config) do
    NewRelic.Transaction.Plug.on_call(conn)
    NewRelic.DistributedTrace.Plug.trace(conn, true)
  end

  def handle_event(
        @plug_stop,
        %{duration: _duration},
        %{conn: conn},
        _config
      ) do
    # TODO: use duration
    NewRelic.Transaction.Plug.before_send(conn)
    NewRelic.DistributedTrace.Plug.before_send(conn)
  end

  def handle_event(
        @plug_exception,
        %{duration: _duration},
        %{conn: conn, kind: kind, reason: reason, stacktrace: stack},
        _config
      ) do
    # TODO: use duration
    conn = %{conn | status: 500}
    NewRelic.Transaction.handle_errors(conn, %{kind: kind, reason: reason, stack: stack})
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end
end
