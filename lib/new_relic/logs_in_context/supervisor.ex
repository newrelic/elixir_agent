defmodule NewRelic.LogsInContext.Supervisor do
  use Supervisor

  @moduledoc false
  @elixir_version_requirement ">= 1.10.0"

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    setup_logs_in_context()
    Supervisor.init([], strategy: :one_for_one)
  end

  def setup_logs_in_context() do
    setup_logs_in_context(
      version_match?: Version.match?(System.version(), @elixir_version_requirement)
    )
  end

  def setup_logs_in_context(version_match?: true) do
    Application.get_env(:new_relic_agent, :logs_in_context, :disabled)
    |> case do
      :disabled ->
        :skip

      :direct ->
        :logger.add_primary_filter(
          :nr_logs_in_context,
          {&NewRelic.LogsInContext.primary_filter/2, %{mode: :direct}}
        )

      :forward ->
        :logger.add_primary_filter(
          :nr_logs_in_context,
          {&NewRelic.LogsInContext.primary_filter/2, %{mode: :forward}}
        )

        Logger.configure_backend(:console, format: {NewRelic.LogsInContext, :format})
    end
  end

  def setup_logs_in_context(_) do
    :skip
  end
end
