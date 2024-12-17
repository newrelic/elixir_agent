defmodule NewRelic.Telemetry.Ecto do
  use GenServer

  @moduledoc """
  Provides `Ecto` instrumentation via `telemetry`.

  Repos are auto-discovered and instrumented. Make sure your Ecto app depends
  on `new_relic_agent` so that the agent can detect when your Repos start.

  We automatically gather:

  * Datastore metrics
  * Transaction Trace segments
  * Transaction datastore attributes
  * Distributed Trace span events

  You can opt-out of this instrumentation as a whole with `:ecto_instrumentation_enabled`
  and specifically of query collection with `:query_collection_enabled` via configuration.
  See `NewRelic.Config` for details.
  """

  @doc false
  def start_link(repo: repo, opts: opts) do
    config = %{
      enabled?: NewRelic.Config.feature?(:ecto_instrumentation),
      collect_db_query?: NewRelic.Config.feature?(:query_collection),
      handler_id: {:new_relic_ecto, repo},
      event: opts[:telemetry_prefix] ++ [:query],
      opts: opts
    }

    GenServer.start_link(__MODULE__, config)
  end

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach(
      config.handler_id,
      config.event,
      &NewRelic.Telemetry.Ecto.Handler.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end
end
