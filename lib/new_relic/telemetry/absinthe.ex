defmodule NewRelic.Telemetry.Absinthe do
  use GenServer

  @moduledoc """
  Provides `Absinthe` instrumentation via `telemetry`

  We automatically gather:

  * Transaction name
  * Distributed Trace span events

  You can opt-out of this instrumentation as a whole with `:absinthe_instrumentation_enabled`
  and specifically of query collection with `:query_collection_enabled` via configuration.
  See `NewRelic.Config` for details.
  """

  @doc false
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
      collect_query?: NewRelic.Config.feature?(:query_collection),
      collect_args?: NewRelic.Config.feature?(:function_argument_collection)
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

  @doc false
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(@operation_start, meas, meta, config) do
    query = read_query(meta.options[:document], collect: config.collect_query?)

    NewRelic.Tracer.Direct.start_span(
      meta.id,
      "Absinthe/Operation",
      system_time: meas.system_time,
      attributes: [
        "absinthe.schema": inspect(meta.options[:schema]),
        "absinthe.query": query
      ]
    )

    NewRelic.add_attributes(
      "absinthe.schema": inspect(meta.options[:schema]),
      "absinthe.query": query
    )

    NewRelic.incr_attributes("absinthe.operation.count": 1)
  end

  def handle_event(@operation_stop, meas, meta, _config) do
    operation = apply(Absinthe.Blueprint, :current_operation, [meta.blueprint])
    span_name = operation_span_name(meta.blueprint.execution.result.emitter)
    transaction_name = transaction_name(meta.blueprint.schema, operation)

    NewRelic.Tracer.Direct.stop_span(
      meta.id,
      name: span_name,
      duration: meas.duration,
      attributes: [
        "absinthe.operation.type": operation.type,
        "absinthe.operation.name": operation.name
      ]
    )

    NewRelic.add_attributes(
      framework_name: transaction_name,
      "absinthe.operation.type": operation.type,
      "absinthe.operation.name": operation.name
    )
  end

  def handle_event(@resolve_field_start, meas, %{resolution: resolution} = meta, config) do
    path = apply(Absinthe.Resolution, :path, [resolution]) |> Enum.join(".")
    resolver_name = resolver_name(resolution.middleware)
    args = read_args(resolution.arguments, collect: config.collect_args?)

    type =
      apply(Absinthe.Type, :name, [
        resolution.definition.schema_node.type,
        resolution.schema
      ])

    NewRelic.Tracer.Direct.start_span(
      meta.id,
      {resolver_name, "#{inspect(resolution.schema)}.#{path}"},
      system_time: meas.system_time,
      attributes: [
        "absinthe.field.path": path,
        "absinthe.field.type": type,
        "absinthe.field.name": resolution.definition.name,
        "absinthe.field.parent_type": resolution.definition.parent_type.name,
        "absinthe.field.arguments": args
      ]
    )
  end

  def handle_event(@resolve_field_stop, meas, meta, _config) do
    NewRelic.Tracer.Direct.stop_span(
      meta.id,
      duration: meas.duration
    )
  end

  defp read_query(query, collect: true), do: query
  defp read_query(_query, collect: false), do: "[NOT_COLLECTED]"

  defp read_args(arguments, collect: true) when map_size(arguments) == 0, do: nil
  defp read_args(arguments, collect: true), do: inspect(arguments, limit: 5, printable_limit: 10)
  defp read_args(_args, collect: false), do: "[NOT_COLLECTED]"

  defp resolver_name(middleware) do
    Enum.find_value(middleware, fn
      {{Absinthe.Resolution, :call}, resolver_fn} ->
        info = Function.info(resolver_fn)

        case Keyword.get(info, :type) do
          :external -> inspect(resolver_fn)
          :local -> "&#{inspect(info[:module])}.anonymous/#{info[:arity]}"
        end

      {{middleware, :call}, _options} ->
        inspect({middleware, :call})

      _ ->
        nil
    end)
  end

  defp operation_span_name(%{type: type, name: name}) when is_binary(name) do
    "Absinthe/Operation/#{to_string(type)}:#{name}"
  end

  defp operation_span_name(%{type: type}) do
    "Absinthe/Operation/#{to_string(type)}"
  end

  defp transaction_name(schema, operation) do
    deepest_path = operation |> collect_deepest_path() |> Enum.join(".")
    "Absinthe/#{inspect(schema)}/#{operation.type}/#{deepest_path}"
  end

  defp collect_deepest_path(%{type: :mutation, selections: [%{name: name} | _]}) do
    [name]
  end

  defp collect_deepest_path(%{type: :subscription, selections: [%{name: name} | _]}) do
    [name]
  end

  defp collect_deepest_path(%{type: :query, selections: [selection]}) do
    collect_deepest_path(selection, [])
  end

  defp collect_deepest_path(%{type: :query}) do
    []
  end

  defp collect_deepest_path(%{selections: selections, name: name}, acc) do
    selections
    |> Enum.reject(fn
      %{name: "__typename"} -> true
      _ -> false
    end)
    |> case do
      [selection] -> collect_deepest_path(selection, acc ++ [name])
      _ -> acc ++ [name]
    end
  end

  defp collect_deepest_path(_, acc) do
    acc
  end
end
