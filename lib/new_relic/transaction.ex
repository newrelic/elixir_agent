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

  @doc false
  def start_transaction(category, name) do
    NewRelic.Transaction.Reporter.start_other_transaction()

    NewRelic.DistributedTrace.generate_new_context()
    |> NewRelic.DistributedTrace.track_transaction(transport_type: "Other")

    NewRelic.add_attributes(
      pid: inspect(self()),
      start_time: System.system_time(),
      start_time_mono: System.monotonic_time(),
      other_transaction_name: "#{category}/#{name}"
    )

    :ok
  end

  @doc false
  def stop_transaction() do
    NewRelic.Transaction.Reporter.stop_other_transaction()

    :ok
  end

  @doc false
  def ignore_transaction() do
    NewRelic.Transaction.Reporter.ignore_transaction()

    :ok
  end
end
