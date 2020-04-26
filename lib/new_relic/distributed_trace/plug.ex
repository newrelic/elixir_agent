defmodule NewRelic.DistributedTrace.Plug do
  @behaviour Plug
  import Plug.Conn
  require Logger

  # Plug that accepts an incoming DT payload and tracks the DT context

  @moduledoc false

  alias NewRelic.DistributedTrace
  alias NewRelic.DistributedTrace.Context

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{private: %{newrelic_dt_instrumented: true}} = conn, _opts) do
    Logger.warn(
      "You have instrumented twice in the same plug! Please `use NewRelic.Transaction` only once."
    )

    conn
  end

  def call(conn, _opts), do: trace(conn, NewRelic.Config.enabled?())

  def trace(conn, false), do: conn

  def trace(conn, true) do
    determine_context(conn)
    |> DistributedTrace.track_transaction(transport_type: "HTTP")

    conn
    |> put_private(:newrelic_dt_instrumented, true)
    |> register_before_send(&before_send/1)
  end

  def before_send(conn) do
    DistributedTrace.cleanup_context()
    conn
  end

  defp determine_context(conn) do
    case DistributedTrace.accept_distributed_trace_headers(:http, conn) do
      %Context{} = context -> context
      _ -> DistributedTrace.generate_new_context()
    end
  end
end
