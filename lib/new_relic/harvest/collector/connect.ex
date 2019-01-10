defmodule NewRelic.Harvest.Collector.Connect do
  def payload do
    [
      %{
        language: "elixir",
        pid: NewRelic.Util.pid(),
        host: NewRelic.Util.hostname(),
        app_name: NewRelic.Config.app_name(),
        labels:
          NewRelic.Config.labels()
          |> Enum.map(fn [key, value] ->
            %{label_type: key, label_value: value}
          end),
        utilization: NewRelic.Util.utilization(),
        environment: NewRelic.Util.elixir_environment(),
        agent_version: NewRelic.Config.agent_version()
      }
    ]
  end
end
