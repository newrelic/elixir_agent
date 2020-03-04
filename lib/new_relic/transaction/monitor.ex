defmodule NewRelic.Transaction.Monitor do
  use GenServer
  alias NewRelic.Transaction
  alias NewRelic.DistributedTrace

  # This GenServer watches transaction processes for
  #  - :trace messages
  #  - :DOWN messages
  #
  # :trace messages signal that a transaction process has
  # spwaned another process. We want to track that process
  # so we can track attributes on the original transaction
  #
  # :DOWN signals that the transaction process is complete, so
  # we tell the reporter to purge its data

  @moduledoc false

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    enable_trace_patterns()
    {:ok, %{pids: %{}, tasks: %{}}}
  end

  # API

  def add(pid), do: GenServer.call(__MODULE__, {:add, pid})

  # Server

  def handle_call({:add, pid}, _from, %{pids: pids} = state) do
    pids =
      pids
      |> Map.has_key?(pid)
      |> setup_monitor(pids, pid)

    {:reply, :ok, %{state | pids: pids}}
  end

  # Trace messages

  def handle_info({:trace_ts, source, :spawn, pid, _mfa, timestamp}, state) do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    {:noreply, state}
  end

  def handle_info({:trace_ts, pid, :exit, _reason, timestamp}, state) do
    Transaction.Reporter.track_exit(pid, NewRelic.Util.time_to_ms(timestamp))
    {:noreply, state}
  end

  def handle_info(
        {:trace_ts, owner, :call, {Task.Supervisor, :async_nolink, [_, _, args]}, _},
        state
      ) do
    state =
      if {:new_relic, :no_track} in args do
        %{state | tasks: Map.put(state.tasks, owner, :no_track)}
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(
        {:trace_ts, source, :return_from, {Task.Supervisor, :async_nolink, _arity},
         %Task{pid: pid, owner: owner}, timestamp},
        state
      ) do
    if state.tasks[owner] == :no_track do
      :no_track
    else
      enable_trace_flags(pid)
      Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    end

    {:noreply, %{state | tasks: Map.delete(state.tasks, owner)}}
  end

  def handle_info(
        {:trace_ts, source, :return_from, {:poolboy, :checkout, _}, pid, timestamp},
        state
      ) do
    Transaction.Reporter.track_spawn(source, pid, NewRelic.Util.time_to_ms(timestamp))
    {:noreply, state}
  end

  def handle_info(
        {:trace_ts, _pid, :call,
         {Ecto.Repo.Supervisor, :start_link, [_repo, otp_app, _adapter, _opts]}, _timestamp},
        state
      ) do
    NewRelic.Telemetry.Ecto.Supervisor.start_child(otp_app)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    Transaction.Reporter.ensure_purge(pid)
    Transaction.Reporter.complete(pid, :async)
    DistributedTrace.Tracker.cleanup(pid)
    {:noreply, %{state | pids: Map.delete(state.pids, pid)}}
  end

  def handle_info(_msg, state) do
    # Ignore other :trace messages
    {:noreply, state}
  end

  # Helpers

  defp setup_monitor(false, pids, pid) do
    Process.monitor(pid)
    enable_trace_flags(pid)
    Map.put(pids, pid, true)
  end

  defp setup_monitor(true, pids, _) do
    pids
  end

  def enable_trace_flags(pid) do
    # Trace process events to notice when a process is spawned
    # Trace function calls so we can install specific trace_patterns
    #   http://erlang.org/doc/man/erlang.html#trace-3
    :erlang.trace(pid, true, [:procs, :call, :set_on_spawn, :timestamp])
  rescue
    # Process is already dead
    ArgumentError ->
      nil
  end

  def enable_trace_patterns do
    # Use function tracers to notice when Async work has been kicked off
    #   http://erlang.org/doc/man/erlang.html#trace_3_trace_messages_return_from
    #   http://erlang.org/doc/apps/erts/match_spec.html
    trace_task_async_nolink()
    trace_poolboy_checkout()
    trace_ecto_repo_discovery()
  end

  defp trace_task_async_nolink do
    :erlang.trace_pattern({Task.Supervisor, :async_nolink, :_}, [{:_, [], [{:return_trace}]}], [])
  end

  defp trace_poolboy_checkout do
    :erlang.trace_pattern({:poolboy, :checkout, :_}, [{:_, [], [{:return_trace}]}], [])
  end

  defp trace_ecto_repo_discovery() do
    Code.ensure_loaded?(Ecto.Repo.Supervisor) &&
      :erlang.trace_pattern({Ecto.Repo.Supervisor, :start_link, :_}, true, [:meta])
  end
end
