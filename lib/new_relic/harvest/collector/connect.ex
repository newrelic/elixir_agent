defmodule NewRelic.Harvest.Collector.Connect do
  @moduledoc false

  def payload do
    [
      %{
        language: "elixir",
        pid: NewRelic.Util.pid(),
        host: NewRelic.Util.hostname(),
        display_host: NewRelic.Config.host_display_name(),
        app_name: NewRelic.Config.app_name(),
        labels:
          Enum.map(NewRelic.Config.labels(), fn [key, value] ->
            %{label_type: key, label_value: value}
          end),
        utilization: NewRelic.Util.utilization(),
        event_harvest_config: NewRelic.Config.event_harvest_config(),
        metadata: NewRelic.Util.metadata(),
        environment: NewRelic.Util.elixir_environment(),
        agent_version: NewRelic.Config.agent_version()
      }
    ]
  end
end
