defmodule NewRelic.Instrumented.Task.Supervisor do
  @moduledoc """
  Provides a pre-instrumented convienince module to connect
  non-linked `Task.Supervisor` processes to the Transaction
  that called them.

  You may call these functions directly, or `alias` the
  `NewRelic.Instrumented.Task` module and continue to use
  `Task` as normal.

  Example usage:
  ```elixir
  alias NewRelic.Instrumented.Task

  Task.Supervisor.async_nolink(
    MySupervisor,
    [1,2],
    fn n -> do_work(n) end
  )
  ```
  """

  import NewRelic.Instrumented.Task.Wrappers

  defdelegate async(supervisor, fun, options \\ []),
    to: Task.Supervisor

  defdelegate async(supervisor, module, fun, args, options \\ []),
    to: Task.Supervisor

  defdelegate children(supervisor),
    to: Task.Supervisor

  defdelegate start_link(options),
    to: Task.Supervisor

  defdelegate terminate_child(supervisor, pid),
    to: Task.Supervisor

  # These functions _don't_ link their Task so we connect them explicitly

  def async_stream(supervisor, enumerable, fun, options \\ []) do
    Task.Supervisor.async_stream(supervisor, enumerable, instrument(fun), options)
  end

  def async_stream(supervisor, enumerable, module, function, args, options \\ []) do
    {module, function, args} = instrument({module, function, args})
    Task.Supervisor.async_stream(supervisor, enumerable, module, function, args, options)
  end

  def async_nolink(supervisor, fun, options \\ []) do
    Task.Supervisor.async_nolink(supervisor, instrument(fun), options)
  end

  def async_nolink(supervisor, module, fun, args, options \\ []) do
    {module, fun, args} = instrument({module, fun, args})
    Task.Supervisor.async_nolink(supervisor, module, fun, args, options)
  end

  def async_stream_nolink(supervisor, enumerable, fun, options \\ []) do
    Task.Supervisor.async_stream_nolink(supervisor, enumerable, instrument(fun), options)
  end

  def async_stream_nolink(supervisor, enumerable, module, function, args, options \\ []) do
    {module, function, args} = instrument({module, function, args})
    Task.Supervisor.async_stream_nolink(supervisor, enumerable, module, function, args, options)
  end

  def start_child(supervisor, fun, options \\ []) do
    Task.Supervisor.start_child(supervisor, instrument(fun), options)
  end

  def start_child(supervisor, module, fun, args, options \\ []) do
    {module, fun, args} = instrument({module, fun, args})
    Task.Supervisor.start_child(supervisor, module, fun, args, options)
  end
end
