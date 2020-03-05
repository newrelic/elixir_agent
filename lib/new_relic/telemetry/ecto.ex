defmodule NewRelic.Telemetry.Ecto do
  use GenServer

  @moduledoc """
  `NewRelic.Telemetry.Ecto` provides `Ecto` instrumentation via `telemetry`.

  Repos are auto-discovered and instrumented. Make sure your Ecto app depends
  on `new_relic_agent` so that the agent can detect when your Repos start.

  We automatically gather:

  * Datastore metrics
  * Transaction Trace segments
  * Transaction datastore attributes
  * Distributed Trace span events

  You can opt-out of this instrumentation as a whole and specifically of
  SQL query collection via configuration. See `NewRelic.Config` for details.
  """

  def start_link(otp_app) do
    enabled = NewRelic.Config.feature?(:ecto_instrumentation)
    ecto_repos = Application.get_env(otp_app, :ecto_repos)
    config = extract_config(otp_app, ecto_repos)

    GenServer.start_link(__MODULE__, config: config, enabled: enabled)
  end

  def init(config: _, enabled: false), do: :ignore

  def init(config: config, enabled: true) do
    log(config)

    :telemetry.attach_many(
      config.handler_id,
      config.events,
      &NewRelic.Telemetry.Ecto.Handler.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  defp extract_config(otp_app, ecto_repos) do
    %{
      otp_app: otp_app,
      events: extract_events(otp_app, ecto_repos),
      repo_configs: extract_repo_configs(otp_app, ecto_repos),
      collect_sql?: NewRelic.Config.feature?(:sql_collection),
      handler_id: {:new_relic_ecto, otp_app}
    }
  end

  defp extract_events(otp_app, ecto_repos) do
    Enum.map(ecto_repos, fn repo ->
      ecto_telemetry_prefix(otp_app, repo) ++ [:query]
    end)
  end

  defp extract_repo_configs(otp_app, ecto_repos) do
    Enum.into(ecto_repos, %{}, fn repo ->
      {repo, extract_repo_config(otp_app, repo)}
    end)
  end

  defp extract_repo_config(otp_app, repo) do
    Application.get_env(otp_app, repo)
    |> Map.new()
    |> case do
      %{url: url} ->
        uri = URI.parse(url)

        %{
          hostname: uri.host,
          port: uri.port,
          database: uri.path |> String.trim_leading("/")
        }

      config ->
        config
    end
  end

  defp ecto_telemetry_prefix(otp_app, repo) do
    Application.get_env(otp_app, repo)
    |> Keyword.get_lazy(:telemetry_prefix, fn ->
      repo
      |> Module.split()
      |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
    end)
  end

  defp log(%{repo_configs: repo_configs}) do
    for {repo, _config} <- repo_configs do
      NewRelic.log(:info, "Detected Ecto Repo `#{inspect(repo)}`")
    end
  end
end
