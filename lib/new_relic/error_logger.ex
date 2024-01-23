defmodule NewRelic.ErrorLogger do
  @moduledoc """
  Handle error reporting in elixir >= 1.15
  """
  @behaviour :gen_event

  import NewRelic.ConditionalCompile

  def init(opts) do
    after_elixir_version(
      "1.15.0",
      Logger.add_translator({__MODULE__, :translator})
    )

    {:ok, opts}
  end

  def handle_call(_opts, state), do: {:ok, :ok, state}

  def handle_event(_opts, state), do: {:ok, state}

  def handle_info(_opts, state), do: {:ok, state}

  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  def terminate(_reason, _state) do
    after_elixir_version(
      "1.15.0",
      Logger.remove_translator({__MODULE__, :translator})
    )

    :ok
  end

  # Don't log SASL progress reports
  def translator(_level, _message, _timestamp, {{caller, :progress}, _})
      when caller in [:supervisor, :application_controller] do
    :skip
  end

  def translator(_level, _message, _timestamp, _metadata), do: :none
end
