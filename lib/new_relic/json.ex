defmodule NewRelic.JSON do
  @moduledoc false

  cond do
    Code.ensure_loaded?(JSON) ->
      def decode(data), do: apply(JSON, :decode, [data])
      def decode!(data), do: apply(JSON, :decode!, [data])
      def encode!(data), do: apply(JSON, :encode!, [data])

    Code.ensure_loaded?(Jason) ->
      def decode(data), do: apply(Jason, :decode, [data])
      def decode!(data), do: apply(Jason, :decode!, [data])
      def encode!(data), do: apply(Jason, :encode!, [data])

    true ->
      raise "[:new_relic_agent] No JSON library found, please add :jason as a dependency"
  end
end
