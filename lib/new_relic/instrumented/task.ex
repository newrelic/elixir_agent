defmodule NewRelic.Instrumented.Task do
  @moduledoc """
  Provides a pre-instrumented convienince module to connect
  non-linked `Task` processes to the Transaction that called them.

  You may call these functions directly, or `alias` the module
  and continue to use `Task` as normal.

  Example usage:
  ```elixir
  alias NewRelic.Instrumented.Task

  Task.async_stream([1,2], fn n -> do_work(n) end)
  ```
  """

  import NewRelic.Instrumented.Task.Wrappers

  defdelegate async(fun),
    to: Task

  defdelegate async(module, function_name, args),
    to: Task

  defdelegate await(task, timeout \\ 5000),
    to: Task

  if Code.ensure_loaded?(Task) && Kernel.function_exported?(Task, :await_many, 2) do
    defdelegate await_many(tasks, timeout \\ 5000),
      to: Task
  end

  defdelegate child_spec(arg),
    to: Task

  defdelegate shutdown(task, timeout \\ 5000),
    to: Task

  defdelegate start_link(fun),
    to: Task

  defdelegate start_link(module, function_name, args),
    to: Task

  defdelegate yield(task, timeout \\ 5000),
    to: Task

  defdelegate yield_many(task, timeout \\ 5000),
    to: Task

  # These functions _don't_ link their Task so we connect them explicitly

  def start(fun) do
    Task.start(instrument(fun))
  end

  def start(module, function_name, args) do
    {module, function_name, args} = instrument({module, function_name, args})
    Task.start(module, function_name, args)
  end

  def async_stream(enumerable, fun, options \\ []) do
    Task.async_stream(enumerable, instrument(fun), options)
  end

  def async_stream(enumerable, module, function_name, args, options \\ []) do
    {module, function_name, args} = instrument({module, function_name, args})
    Task.async_stream(enumerable, module, function_name, args, options)
  end
end
