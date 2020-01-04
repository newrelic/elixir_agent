defmodule NewRelic.Telemetry.EctoSupervisor do
  use Supervisor

  @moduledoc false

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    supervise(ecto_workers(), strategy: :one_for_one)
  end

  def ecto_workers() do
    discover_ecto_otp_apps()
    |> Enum.map(&ecto_worker/1)
  end

  def discover_ecto_otp_apps() do
    Application.loaded_applications()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&Application.get_env(&1, :ecto_repos))
  end

  def ecto_worker(otp_app) do
    worker(NewRelic.Telemetry.Ecto, [otp_app], id: make_ref())
  end
end
