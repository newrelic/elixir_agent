defmodule NewRelic.Harvest.Collector.Connect do
  @moduledoc false

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

  def parse_connect(
        %{"agent_run_id" => _, "messages" => [%{"message" => message}]} = connect_response
      ) do
    NewRelic.log(:info, message)
    connect_response
  end

  def parse_connect(%{"error_type" => _, "message" => message}) do
    NewRelic.log(:error, message)
    :error
  end

  def parse_connect({:error, reason}) do
    NewRelic.log(:error, "Failed connect #{inspect(reason)}")
    :error
  end

  def parse_connect(503) do
    NewRelic.log(:error, "Collector unavailable")
    :error
  end
end
