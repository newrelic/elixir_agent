defmodule NewRelic.Telemetry.Ecto.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  @ecto_repo_init [:ecto, :repo, :init]

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :telemetry.attach(
      {:new_relic_ecto, :supervisor},
      @ecto_repo_init,
      &__MODULE__.handle_event/4,
      %{}
    )

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def handle_event(@ecto_repo_init, _, %{repo: repo, opts: opts}, _) do
    NewRelic.log(:info, "Detected Ecto Repo `#{inspect(repo)}`")

    DynamicSupervisor.start_child(
      __MODULE__,
      {NewRelic.Telemetry.Ecto, [repo: repo, opts: opts]}
    )
  end
end
