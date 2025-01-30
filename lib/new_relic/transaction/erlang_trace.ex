defmodule NewRelic.Transaction.ErlangTrace do
  use GenServer, restart: :temporary

  alias NewRelic.Transaction

  # This GenServer watches Transaction processes for
  # :trace messages that signal that a Transaction process has
  # spwaned another linked process that we include in the Transaction

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @overload_queue_len 500
  @overload_backoff 60 * 1000

  def init(:ok) do
    NewRelic.sample_process()
    enable_trace_patterns()

    overload = %{
      queue_len: Application.get_env(:new_relic_agent, :overload_queue_len, @overload_queue_len),
      backoff: Application.get_env(:new_relic_agent, :overload_backoff, @overload_backoff)
    }

    {:ok, %{overload: overload}}
  end

  # API

  def trace() do
    enable_trace_flags(:self)
  end

  def disable() do
    GenServer.call(__MODULE__, :disable)
  end

  # Server

  def handle_call(:disable, _from, state) do
    {:stop, {:shutdown, :disable}, :ok, state}
  end

  # Trace messages

  def handle_info(
        {:trace_ts, source, :return_from, {module, :spawn_link, _}, pid, timestamp},
        state
      )
      when module in [:proc_lib, Task.Supervised] do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    overload_protection(state.overload)
    {:noreply, state}
  end

  def handle_info(
        {:trace_ts, source, :return_from, {module, :start_link, _}, {:ok, pid}, timestamp},
        state
      )
      when module in [:proc_lib, Task.Supervised] do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    overload_protection(state.overload)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Helpers

  # Trace function calls so we can install specific trace_patterns
  #   http://erlang.org/doc/man/erlang.html#trace-3

  defp enable_trace_flags(:self) do
    with tracer when is_pid(tracer) <- Process.whereis(__MODULE__) do
      :erlang.trace(self(), true, [:call, :set_on_spawn, :timestamp, tracer: tracer])
    end
  rescue
    ArgumentError -> :process_gone
  end

  defp enable_trace_patterns do
    # Use function tracers to notice when linked work has been kicked off
    #   http://erlang.org/doc/man/erlang.html#trace_3_trace_messages_return_from
    #   http://erlang.org/doc/apps/erts/match_spec.html

    trace_proc_lib_spawn_link()
    trace_task_supervised_spawn_link()
  end

  defp trace_proc_lib_spawn_link do
    :erlang.trace_pattern({:proc_lib, :spawn_link, :_}, [{:_, [], [{:return_trace}]}], [])
    :erlang.trace_pattern({:proc_lib, :start_link, :_}, [{:_, [], [{:return_trace}]}], [])
  end

  # Starting with elixir 1.15 tasks are spawned with Task.Supervised.
  # See https://github.com/elixir-lang/elixir/commit/ecdf68438160928f01769b3ed76e184ad451c9fe
  if NewRelic.Util.ConditionalCompile.match?(">= 1.15.0") do
    defp trace_task_supervised_spawn_link do
      :erlang.trace_pattern({Task.Supervised, :spawn_link, :_}, [{:_, [], [{:return_trace}]}], [])
      :erlang.trace_pattern({Task.Supervised, :start_link, :_}, [{:_, [], [{:return_trace}]}], [])
    end
  else
    defp trace_task_supervised_spawn_link do
      :ignore
    end
  end

  defp overload_protection(%{backoff: backoff} = overload) do
    {:message_queue_len, len} = Process.info(self(), :message_queue_len)

    cond do
      len >= overload.queue_len ->
        NewRelic.log(:error, "ErlangTrace overload: #{len} - shutting down for #{backoff} ms.")
        NewRelic.Transaction.ErlangTraceManager.enable_erlang_trace(after: overload.backoff)
        exit({:shutdown, :overload})

      true ->
        :all_good
    end
  end
end
