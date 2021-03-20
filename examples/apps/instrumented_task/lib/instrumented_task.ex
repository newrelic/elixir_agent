defmodule Mix.Tasks.InstrumentedTask do
  use Mix.Task
  use NewRelic.Instrumented.Mix.Task

  def run(_) do
    IO.puts("Instrumented Task exectued")
  end
end
