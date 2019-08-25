defmodule NewRelic.GracefulShutdown do
  @moduledoc false
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    Process.flag(:trap_exit, true)
    {:ok, nil}
  end

  def terminate(_reason, _state) do
    NewRelic.log(:info, "Attempting graceful shutdown")
    NewRelic.Error.Supervisor.remove_handler()
    NewRelic.Harvest.Supervisor.manual_shutdown()
  end
end
