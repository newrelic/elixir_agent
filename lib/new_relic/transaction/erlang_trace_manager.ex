defmodule NewRelic.Transaction.ErlangTraceManager do
  use GenServer

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:ok, %{restarts: 0}}
  end

  def restart_count() do
    GenServer.call(__MODULE__, :restart_count)
  end

  def handle_info(:enable, state) do
    NewRelic.log(:debug, "ErlangTrace: restart number #{state.restarts + 1}")
    enable_erlang_trace()
    {:noreply, %{state | restarts: state.restarts + 1}}
  end

  def handle_call(:restart_count, _from, state) do
    {:reply, state.restarts, state}
  end

  def disable_erlang_trace do
    NewRelic.Transaction.ErlangTrace.disable()
  end

  def enable_erlang_trace do
    Supervisor.start_child(
      NewRelic.Transaction.ErlangTraceSupervisor,
      Supervisor.child_spec(NewRelic.Transaction.ErlangTrace, [])
    )
  end

  def enable_erlang_trace(after: after_ms) do
    Process.send_after(__MODULE__, :enable, after_ms)
  end
end
