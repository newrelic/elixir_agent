defmodule NewRelic.Telemetry.Absinthe.Metadata do
  alias Absinthe.Language.OperationDefinition

  def resolver_name(middleware) do
    Enum.find_value(middleware, fn
      {{Absinthe.Resolution, :call}, resolver_fn} ->
        info = Function.info(resolver_fn)

        case Keyword.get(info, :type) do
          :external -> inspect(resolver_fn)
          :local -> local_function_name(info)
        end

      {{middleware, :call}, _options} ->
        inspect({middleware, :call})

      _ ->
        nil
    end)
  end

  defp local_function_name(info) do
    case Atom.to_string(info[:name]) do
      "-dataloader" <> _ -> "&#{inspect(info[:module])}.dataloader/#{info[:arity]}"
      _ -> "&#{inspect(info[:module])}.anonymous/#{info[:arity]}"
    end
  end

  def operation_span_name(input) when is_binary(input) do
    with {:ok, tokens} <- Absinthe.Lexer.tokenize(input),
         {:ok, parsed} <- :absinthe_parser.parse(tokens) do
      definition =
        for %OperationDefinition{operation: operation} = d <- parsed.definitions,
            operation in [:query, :mutation] do
          d
        end
        |> List.first()

      unless is_nil(definition) do
        "#{definition.operation}:#{definition.name || definition.selection_set.selections |> selections_name()}"
      end
    end
  end

  def operation_span_name(%{type: type}) do
    "#{to_string(type)}"
  end

  def operation_span_name(%{type: type, name: name}) when is_binary(name) do
    "#{to_string(type)}:#{name}"
  end

  def operation_span_name(nil) do
    "Absinthe/unknown_operation"
  end

  def transaction_name(schema, %Absinthe.Blueprint.Document.Operation{} = operation) do
    "Absinthe/#{inspect(schema)}/#{operation.type}/#{operation.name || operation.selections |> selections_name()}"
  end

  def transaction_name(schema, nil) do
    "Absinthe/#{inspect(schema)}/unknown_operation"
  end

  defp selections_name(selections) do
    selections |> Enum.map(fn x -> Map.get(x, :name) end) |> Enum.join("+")
  end
end
