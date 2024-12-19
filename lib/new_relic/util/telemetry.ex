defmodule NewRelic.Util.Telemetry do
  @moduledoc false

  def reason_and_stack(%{reason: %{__exception__: true} = reason, stacktrace: stack}) do
    {reason, stack}
  end

  def reason_and_stack(%{reason: {{reason, stack}, _init_call}}) do
    {reason, stack}
  end

  def reason_and_stack(%{reason: {reason, _init_call}}) do
    {reason, []}
  end

  def reason_and_stack(unexpected_exception) do
    NewRelic.log(:debug, "unexpected_exception: #{inspect(unexpected_exception)}")
    {:unexpected_exception, []}
  end
end
