defmodule NewRelic.Transaction do
  @moduledoc false

  @deprecated "Plug is now auto-instrumented via `telemetry`, please remove manual instrumentation."
  defmacro __using__(_) do
    quote do
      :not_needed!
    end
  end

  @deprecated "Plug is now auto-instrumented via `telemetry`, please remove manual instrumentation."
  def handle_errors(_conn, _error) do
    :not_needed!
  end
end
