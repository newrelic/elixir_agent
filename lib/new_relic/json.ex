defmodule NewRelic.JSON do
  @moduledoc false

  if Code.ensure_loaded?(JSON) do
    defdelegate decode(data), to: JSON
    defdelegate decode!(data), to: JSON
    defdelegate encode!(data), to: JSON
  end

  if Code.ensure_loaded?(Jason) do
    defdelegate decode(data), to: Jason
    defdelegate decode!(data), to: Jason
    defdelegate encode!(data), to: Jason
  end
end
