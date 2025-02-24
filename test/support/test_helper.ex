defmodule TestHelper do
  def request(module, conn, http_opts \\ [], protocol_options \\ []) do
    Plug.Cowboy.http(module, [], port: 8000, protocol_options: protocol_options)

    response =
      NewRelic.Util.HTTP.get(
        "http://localhost:8000#{conn.request_path}",
        conn.req_headers,
        http_opts
      )

    Plug.Cowboy.shutdown(Module.concat(module, HTTP))

    case response do
      {:ok, response} -> response
      response -> response
    end
  end

  def http_request(port, path) do
    {:ok, {{_, status_code, _}, _headers, body}} =
      :httpc.request(~c"http://localhost:#{port}/#{path}")

    {:ok, %{status_code: status_code, body: to_string(body)}}
  end

  def trigger_report(module) do
    Process.sleep(300)
    GenServer.call(module, :report)
  end

  def gather_harvest(harvester) do
    Process.sleep(300)
    harvester.gather_harvest()
  end

  def restart_harvest_cycle(harvest_cycle) do
    Process.sleep(300)
    GenServer.call(harvest_cycle, :restart)
  end

  def pause_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :pause)
  end

  def find_metric(metrics, name, call_count \\ 1)

  def find_metric(metrics, {name, scope}, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name, scope: ^scope}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end

  def find_metric(metrics, name, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name, scope: ""}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end

  def find_span(spans, name) do
    Enum.find_value(spans, fn
      [%{name: ^name} = span, _, _] -> span
      _span -> false
    end)
  end

  def simulate_agent_enabled() do
    Process.whereis(Harvest.TaskSupervisor) ||
      NewRelic.EnabledSupervisor.start_link(:ok)

    :ok
  end

  def simulate_agent_run(extra_nr_config \\ []) do
    TestHelper.run_with(:nr_config, Keyword.merge([license_key: "dummy_key", harvest_enabled: true], extra_nr_config))
    TestHelper.run_with(:nr_agent_run, trusted_account_key: "190", account_id: 190)
    NewRelic.DistributedTrace.BackoffSampler.reset()

    :ok
  end

  # :application_config
  #  - internal agent configuration values

  def run_with(:application_config, [{key, value}]) do
    original = Application.get_env(:new_relic_agent, key)

    Application.put_env(:new_relic_agent, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case original do
        nil -> Application.delete_env(:new_relic_agent, key)
        original -> Application.put_env(:new_relic_agent, key, original)
      end
    end)
  end

  def run_with(:logs_in_context, mode) do
    :logger.remove_primary_filter(:nr_logs_in_context)
    NewRelic.LogsInContext.configure(mode)

    ExUnit.Callbacks.on_exit(fn ->
      :logger.remove_primary_filter(:nr_logs_in_context)
    end)
  end

  # :nr_config
  #  - user facing agent configuration, ex: NewRelic.Config.app_name
  #  - determined and set in NewRelic.Init

  # :nr_features
  #  - user facing agent feature configuration, ex: NewRelic.Config.feature(:key)
  #  - determined and set in NewRelic.Init

  # :nr_agent_run
  #  - Agent configuration that comes from collector, ex: AgentRun.entity_guid
  #  - determined and set in NewRelic.Harvest.Collector.AgentRun

  def run_with(key, updates) do
    original = :persistent_term.get(key, %{})
    updates = Map.new(updates)

    :persistent_term.put(key, Map.merge(original, updates))

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.put(key, original)
    end)
  end
end
