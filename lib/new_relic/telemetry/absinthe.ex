defmodule NewRelic.Telemetry.Absinthe do
  use GenServer

  @moduledoc """
  Provides `Absinthe` instrumentation via `telemetry`

  We automatically gather:

  * Transaction name
  * Distributed Trace span events

  You can opt-out of this instrumentation as a whole and specifically of
  query collection via configuration. See `NewRelic.Config` for details.
  """
  @doc false

  alias NewRelic.Telemetry.Absinthe.Metadata

  def start_link(_) do
    enabled = NewRelic.Config.feature?(:absinthe_instrumentation)
    GenServer.start_link(__MODULE__, [enabled: enabled], name: __MODULE__)
  end

  @operation_start [:absinthe, :execute, :operation, :start]
  @operation_stop [:absinthe, :execute, :operation, :stop]
  @resolve_field_start [:absinthe, :resolve, :field, :start]
  @resolve_field_stop [:absinthe, :resolve, :field, :stop]

  @events [
    @operation_start,
    @operation_stop,
    @resolve_field_start,
    @resolve_field_stop
  ]

  @doc false
  def init(enabled: false), do: :ignore

  def init(enabled: true) do
    config = %{
      handler_id: {:new_relic, :absinthe},
      collect_query?: NewRelic.Config.feature?(:db_query_collection)
    }

    :telemetry.attach_many(
      config.handler_id,
      @events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(@operation_start, meas, meta, config) do
    NewRelic.start_span(
      id: meta.id,
      name: Metadata.operation_span_name(meta.blueprint.input),
      start_time: meas.system_time,
      attributes: [
        "absinthe.query": read_query(meta.options[:document], collect: config.collect_query?),
        start_time_mono: System.monotonic_time()
      ]
    )

    NewRelic.incr_attributes("absinthe.operation.count": 1)
  end

  def handle_event(@resolve_field_start, meas, meta, _config) do
    path = Absinthe.Resolution.path(meta.resolution)
    parent_path = parent_path(path)

    type = "#{meta.resolution.definition.parent_type.name}.#{meta.resolution.definition.name}"
    resolver_name = Metadata.resolver_name(meta.resolution.middleware)

    NewRelic.start_span(
      id: meta.id,
      name: resolver_name,
      start_time: meas.system_time,
      path: Enum.join(path, "."),
      parent_path: Enum.join(parent_path, "."),
      attributes: [
        "absinthe.field.path": Enum.join(path, "."),
        "absinthe.field.type": type,
        start_time_mono: System.monotonic_time()
      ]
    )
  end

  def handle_event(@resolve_field_stop, meas, meta, _config) do
    path = Absinthe.Resolution.path(meta.resolution)
    type = "#{meta.resolution.definition.parent_type.name}.#{meta.resolution.definition.name}"

    NewRelic.stop_span(
      id: meta.id,
      duration: meas.duration,
      path: Enum.join(path, "."),
      attributes: [
        "absinthe.field.path": Enum.join(path, "."),
        "absinthe.field.type": type
      ],
      aggregate: %{
        name: :AbsintheResolverTrace,
        method_key: :resolver
      },
      is_segment?: true
    )
  end

  def handle_event(@operation_stop, meas, meta, _config) do
    operation = Absinthe.Blueprint.current_operation(meta.blueprint)

    NewRelic.add_attributes(
      framework_name: Metadata.transaction_name(meta.blueprint.schema, operation)
    )

    NewRelic.stop_span(
      id: meta.id,
      duration: meas.duration,
      attributes: [
        "absinthe.operation.type": operation && operation.type,
        "absinthe.operation.name": operation && operation.name
      ],
      aggregate: %{
        name: :AbsintheOperationTrace,
        method_key: :operation
      }
    )
  end

  def parent_path(path) when is_list(path) do
    case Enum.take(path, -2) do
      [i, _] when is_number(i) -> path |> Enum.drop(-2)
      _ -> path |> Enum.drop(-1)
    end
  end

  defp read_query(query, collect: true), do: query
  defp read_query(_query, collect: false), do: "[NOT_COLLECTED]"
end
