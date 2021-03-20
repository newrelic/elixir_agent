defmodule Mix.Tasks.UninstrumentedTask do
  use Mix.Task

  @moduledoc """
  If the new_relic_agent application isn't even started,
  calls to instrumentation functions should not fail
  """
  def run(_) do
    NewRelic.report_custom_metric("My/Metric", 123)

    IO.puts("Uninstrumented Task exectued")
  end
end
