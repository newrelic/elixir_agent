defmodule NewRelic.Transaction.ErlangTrace do
  use GenServer, restart: :temporary

  alias NewRelic.Transaction

  # This GenServer watches transaction processes for
  # :trace messages signal that a transaction process has
  # spwaned another process that we track as a Span

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
    GenServer.cast(__MODULE__, {:trace, self()})
  end

  def disable() do
    GenServer.call(__MODULE__, :disable)
  end

  # Server

  def handle_cast({:trace, pid}, state) do
    enable_trace_flags(pid)

    {:noreply, state}
  end

  def handle_call(:disable, _from, state) do
    {:stop, {:shutdown, :disable}, :ok, state}
  end

  # Trace messages

  def handle_info(
        {:trace_ts, source, :return_from, {Task.Supervisor, :async_nolink, _arity},
         %Task{pid: pid}, timestamp},
        state
      ) do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    enable_trace_flags(pid)
    overload_protection(state.overload)
    {:noreply, state}
  end

  def handle_info(
        {:trace_ts, source, :return_from, {:poolboy, :checkout, _}, pid, timestamp},
        state
      ) do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    overload_protection(state.overload)
    {:noreply, state}
  end

  def handle_info(
        {:trace_ts, source, :return_from, {:proc_lib, :spawn_link, _}, pid, timestamp},
        state
      ) do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    overload_protection(state.overload)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Helpers

  def enable_trace_flags(pid) do
    # Trace function calls so we can install specific trace_patterns
    #   http://erlang.org/doc/man/erlang.html#trace-3

    :erlang.trace(pid, true, [:call, :set_on_spawn, :timestamp])
  rescue
    # Process is already dead
    ArgumentError -> nil
  end

  def enable_trace_patterns do
    # Use function tracers to notice when Async work has been kicked off
    #   http://erlang.org/doc/man/erlang.html#trace_3_trace_messages_return_from
    #   http://erlang.org/doc/apps/erts/match_spec.html

    trace_proc_lib_spawn_link()
    trace_task_async_nolink()
    trace_poolboy_checkout()
  end

  defp trace_proc_lib_spawn_link do
    :erlang.trace_pattern({:proc_lib, :spawn_link, :_}, [{:_, [], [{:return_trace}]}], [])
  end

  defp trace_task_async_nolink do
    :erlang.trace_pattern({Task.Supervisor, :async_nolink, :_}, [{:_, [], [{:return_trace}]}], [])
  end

  defp trace_poolboy_checkout do
    :erlang.trace_pattern({:poolboy, :checkout, :_}, [{:_, [], [{:return_trace}]}], [])
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
