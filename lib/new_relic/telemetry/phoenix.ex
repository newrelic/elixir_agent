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
  @phoenix_error [:phoenix, :error_rendered]

  @phoenix_events [
    @phoenix_router_start,
    @phoenix_error
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    IO.inspect(:ATTACH)

    :telemetry.attach_many(
      config.handler_id,
      @phoenix_events,
      &__MODULE__.handle_event/4,
      config
    )

    # Process.flag(:trap_exit, true)
    {:ok, config}
  end

  @doc false
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(
        @phoenix_router_start,
        _measurements,
        %{conn: conn} = meta,
        _config
      ) do
    IO.inspect({@phoenix_router_start, phoenix_name(meta)})
    Process.flag(:trap_exit, true)

    [
      phoenix_name: phoenix_name(meta),
      "phoenix.endpoint": conn.private[:phoenix_endpoint] |> inspect(),
      "phoenix.router": conn.private[:phoenix_router] |> inspect(),
      "phoenix.controller": meta.plug |> inspect(),
      "phoenix.action": meta.plug_opts |> to_string()
      # phoenix_layout
      # phoenix_view
    ]
    |> NewRelic.add_attributes()
  end

  # todo:
  # what can we get for a 404?
  # def handle_event(
  #       @phoenix_error,
  #       _measurements,
  #       %{conn: conn, status: 404} = meta,
  #       _config
  #     ) do
  #   IO.inspect({@phoenix_error, 404})

  #   [
  #     phoenix_name: phoenix_name(meta),
  #     "phoenix.endpoint": conn.private[:phoenix_endpoint] |> inspect(),
  #     "phoenix.router": conn.private[:phoenix_router] |> inspect()
  #   ]
  #   |> NewRelic.add_attributes()
  # end

  def handle_event(
        @phoenix_error,
        measurements,
        meta,
        _config
      ) do
    IO.inspect({@phoenix_error,measurements, meta})
  end

  defp phoenix_name(%{plug: controller, plug_opts: action}) do
    "/Phoenix/#{inspect(controller)}/#{action}"
  end

  defp phoenix_name(%{conn: conn}) do
    "/Phoenix/#{inspect(conn.private[:phoenix_endpoint])}/#{conn.method}"
  end
end
