defmodule NewRelic.Telemetry.Phoenix do
  use GenServer

  @moduledoc """
  Provides `Phoenix` instrumentation via `telemetry`.

  This instrumentation adds extra Phoenix specific instrumentation
  on top of the base `NewRelic.Telemetry.Plug` instrumentation.
  """
  def start_link(_) do
    config = %{
      enabled?: NewRelic.Config.feature?(:phoenix_instrumentation),
      handler_id: {:new_relic, :phoenix}
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @phoenix_router_start [:phoenix, :router_dispatch, :start]

  @phoenix_events [
    @phoenix_router_start
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach_many(
      config.handler_id,
      @phoenix_events,
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
        @phoenix_router_start,
        _measurements,
        %{conn: conn, route: route} = meta,
        _config
      ) do
    [
      phoenix_name: phoenix_name(conn, route),
      "phoenix.endpoint": conn.private[:phoenix_endpoint] |> inspect(),
      "phoenix.router": conn.private[:phoenix_router] |> inspect(),
      "phoenix.controller": meta.plug |> inspect(),
      "phoenix.action": meta.plug_opts |> to_string()
    ]
    |> NewRelic.add_attributes()
  end

  defp phoenix_name(conn, route),
    do:
      "/Phoenix/#{conn.method}/#{route}"
      |> String.replace("/*glob", "")
      |> String.replace("/*_path", "")
end
