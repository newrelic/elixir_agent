defmodule NewRelic.DistributedTrace.Plug do
  @behaviour Plug
  import Plug.Conn
  require Logger

  # Plug that accepts an incoming DT payload and tracks the DT context

  @moduledoc false

  alias NewRelic.DistributedTrace
  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun

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

  defp before_send(conn) do
    DistributedTrace.cleanup_context()
    conn
  end

  defp determine_context(conn) do
    with %Context{} = context <- DistributedTrace.accept_distributed_trace_payload(:http, conn),
         %Context{} = context <- restrict_access(context) do
      context
    else
      _ -> DistributedTrace.generate_new_context()
    end
  end

  def restrict_access(context) do
    if (context.trust_key || context.account_id) == AgentRun.trusted_account_key() do
      context
    else
      :restricted
    end
  end
end
