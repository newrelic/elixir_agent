defmodule NewRelic.Harvest.Collector.AgentRun do
  use GenServer

  # This GenServer is responsible for connecting to the collector
  # and holding onto the Agent Run connect response in an ETS table

  @moduledoc false

  alias NewRelic.Harvest.Collector

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    :ets.new(__MODULE__, [:named_table, :public, :set])

    if NewRelic.Config.enabled?() do
      {:ok, %{status: :not_connected}, {:continue, :preconnect}}
    else
      {:ok, %{status: :not_connected}}
    end
  end

  def ensure_initialized do
    GenServer.call(__MODULE__, :ping)
  end

  def agent_run_id, do: get(:agent_run_id)
  def entity_guid, do: get(:entity_guid)
  def trusted_account_key, do: get(:trusted_account_key)
  def account_id, do: get(:account_id)
  def primary_application_id, do: get(:primary_application_id)
  def apdex_t, do: get(:apdex_t)
  def request_headers, do: get(:request_headers)

  def reconnect, do: send(__MODULE__, :reconnect)

  def handle_continue(:preconnect, _state) do
    case Collector.Protocol.preconnect() do
      {:ok, %{"redirect_host" => redirect_host}} ->
        Application.put_env(:new_relic_agent, :collector_instance_host, redirect_host)
        {:noreply, %{status: :preconnected}, {:continue, :connect}}

      _error ->
        {:noreply, %{status: :error_during_preconnect}}
    end
  end

  def handle_continue(:connect, _state) do
    status = connect()
    {:noreply, %{status: status}, {:continue, :complete_boot}}
  end

  def handle_continue(:complete_boot, %{status: :connected} = state) do
    NewRelic.EnabledSupervisorManager.start_child()
    {:noreply, state}
  end

  def handle_continue(:complete_boot, state) do
    {:noreply, state}
  end

  def handle_info(:reconnect, _state) do
    status = connect()
    {:noreply, %{status: status}}
  end

  def handle_call(:ping, _from, state) do
    {:reply, true, state}
  end

  defp connect() do
    Collector.Connect.payload()
    |> Collector.Protocol.connect()
    |> store_agent_run()
  end

  defp get(key),
    do: :persistent_term.get(:nr_agent_run, %{})[key]

  defp store_agent_run({:ok, %{"agent_run_id" => _} = connect_response}) do
    :persistent_term.put(:nr_entity_metadata, %{
      hostname: NewRelic.Util.hostname(),
      "entity.type": "SERVICE",
      "entity.guid": connect_response["entity_guid"],
      "entity.name": NewRelic.Config.app_name() |> List.first()
    })

    :persistent_term.put(:nr_agent_run, %{
      agent_run_id: connect_response["agent_run_id"],
      entity_guid: connect_response["entity_guid"],
      trusted_account_key: connect_response["trusted_account_key"],
      account_id: connect_response["account_id"],
      primary_application_id: connect_response["primary_application_id"],
      apdex_t: connect_response["apdex_t"],
      request_headers: connect_response["request_headers_map"] |> Map.to_list()
    })

    store(:sampling_target, connect_response["sampling_target"])
    store(:sampling_target_period, connect_response["sampling_target_period_in_seconds"] * 1000)

    connect_response["data_methods"]
    event_harvest = connect_response["event_harvest_config"]
    harvest_limits = event_harvest["harvest_limits"]

    if harvest_limits["analytic_event_data"] do
      store(:transaction_event_reservoir_size, harvest_limits["analytic_event_data"])
      store(:transaction_event_harvest_cycle, event_harvest["report_period_ms"])
    else
      analytic_event = connect_response["data_methods"]["analytic_event_data"]
      store(:transaction_event_reservoir_size, analytic_event["max_samples_stored"])
      store(:transaction_event_harvest_cycle, analytic_event["report_period_in_seconds"] * 1000)
    end

    if harvest_limits["custom_event_data"] do
      store(:custom_event_reservoir_size, harvest_limits["custom_event_data"])
      store(:custom_event_harvest_cycle, event_harvest["report_period_ms"])
    else
      custom_event = connect_response["data_methods"]["custom_event_data"]
      store(:custom_event_reservoir_size, custom_event["max_samples_stored"])
      store(:custom_event_harvest_cycle, custom_event["report_period_in_seconds"] * 1000)
    end

    if harvest_limits["error_event_data"] do
      store(:error_event_reservoir_size, harvest_limits["error_event_data"])
      store(:error_event_harvest_cycle, event_harvest["report_period_ms"])
    else
      error_event = connect_response["data_methods"]["error_event_data"]
      store(:error_event_reservoir_size, error_event["max_samples_stored"])
      store(:error_event_harvest_cycle, error_event["report_period_in_seconds"] * 1000)
    end

    if harvest_limits["span_event_data"] do
      store(:span_event_reservoir_size, harvest_limits["span_event_data"])
      store(:span_event_harvest_cycle, event_harvest["report_period_ms"])
    else
      span_event = connect_response["data_methods"]["span_event_data"]
      store(:span_event_reservoir_size, span_event["max_samples_stored"])
      store(:span_event_harvest_cycle, span_event["report_period_in_seconds"] * 1000)
    end

    store(:data_report_period, connect_response["data_report_period"] * 1000)

    :connected
  end

  defp store_agent_run(_bad_connect_response) do
    :bad_connect_response
  end

  @empty_entity_metadata %{
    "entity.type": "SERVICE",
    "entity.guid": nil,
    "entity.name": nil
  }
  def entity_metadata() do
    :persistent_term.get(:nr_entity_metadata, @empty_entity_metadata)
  end

  defp store(key, value) do
    :ets.insert(__MODULE__, {key, value})
  end

  def lookup(key, default \\ nil) do
    Application.get_env(:new_relic_agent, key) ||
      case :ets.lookup(__MODULE__, key) do
        [{^key, value}] -> value
        [] -> default
      end
  end
end
