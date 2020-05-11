defmodule Mix.Tasks.InstrumentedTask.ExampleTask do
  use Mix.Task
  use NewRelic.Instrumented.Mix.Task

  def run(_) do
    IO.puts("Task exectued")
  end
end
