defmodule NewRelic.ErrorLogger do
  @moduledoc false
  require Logger
  @behaviour :gen_event

  def init(_) do
    Logger.warning("`NewRelic.ErrorLogger` no longer needed, please remove it from :logger configuration")
    {:ok, nil}
  end

  def handle_call(_opts, state), do: {:ok, :ok, state}
  def handle_event(_opts, state), do: {:ok, state}
  def handle_info(_opts, state), do: {:ok, state}
  def code_change(_old_vsn, state, _extra), do: {:ok, state}
  def terminate(_reason, _state), do: :ok
end
