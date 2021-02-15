defmodule NewRelic.SignalHandler do
  @moduledoc false
  @behaviour :gen_event

  # This signal handler exists so that we can shut down
  # the NewRelic.Sampler.Beam process asap to avoid a race
  # condition that can happen while `cpu_sup` shuts down

  def start do
    case Process.whereis(:erl_signal_server) do
      pid when is_pid(pid) ->
        # Get our signal handler installed before erlang's
        :gen_event.delete_handler(:erl_signal_server, :erl_signal_handler, :ok)
        :gen_event.add_handler(:erl_signal_server, __MODULE__, [])
        :gen_event.add_handler(:erl_signal_server, :erl_signal_handler, [])

      _ ->
        :ok
    end
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_event(:sigterm, state) do
    Process.whereis(NewRelic.Sampler.Beam) &&
      GenServer.stop(NewRelic.Sampler.Beam)

    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_call(_, state) do
    {:ok, :ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  def code_change(_old, state, _extra) do
    {:ok, state}
  end
end
