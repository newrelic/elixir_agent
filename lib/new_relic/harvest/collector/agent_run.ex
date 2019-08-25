defmodule NewRelic.Harvest.Collector.AgentRun do
  use GenServer

  # This GenServer is responsible for connecting to the collector
  # and holding onto the Agent Run state

  @moduledoc false

  alias NewRelic.Harvest.Collector

  def start_link do
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

  def agent_run_id, do: lookup(:agent_run_id)
  def trusted_account_key, do: lookup(:trusted_account_key)
  def account_id, do: lookup(:account_id)
  def primary_application_id, do: lookup(:primary_application_id)

  def reconnect, do: send(__MODULE__, :reconnect)

  def handle_continue(:preconnect, _state) do
    case Collector.Protocol.preconnect() do
      %{"redirect_host" => redirect_host} ->
        Application.put_env(:new_relic_agent, :collector_instance_host, redirect_host)
        {:noreply, %{status: :preconnected}, {:continue, :connect}}

      {:error, _reason} ->
        {:noreply, %{status: :error_during_preconnect}}

      {:failed_connect, _reason} ->
        {:noreply, %{status: :failed_to_preconnect}}
    end
  end

  def handle_continue(:connect, _state) do
    {:noreply, connect()}
  end

  def handle_info(:reconnect, _state) do
    {:noreply, connect()}
  end

  def handle_call(:connected, _from, state) do
    {:reply, true, state}
  end

  defp connect() do
    Collector.Connect.payload()
    |> Collector.Protocol.connect()
    |> Collector.Connect.parse_connect()
    |> store_agent_run
  end

  defp store_agent_run(%{"agent_run_id" => _} = state) do
    store(:agent_run_id, state["agent_run_id"])
    store(:trusted_account_key, state["trusted_account_key"])
    store(:account_id, state["account_id"])
    store(:primary_application_id, state["primary_application_id"])

    store(:sampling_target, state["sampling_target"])
    store(:sampling_target_period, state["sampling_target_period_in_seconds"] * 1000)

    transaction_event = state["data_methods"]["analytic_event_data"]
    store(:transaction_event_reservoir_size, transaction_event["max_samples_stored"])
    store(:transaction_event_harvest_cycle, transaction_event["report_period_in_seconds"] * 1000)

    custom_event = state["data_methods"]["custom_event_data"]
    store(:custom_event_reservoir_size, custom_event["max_samples_stored"])
    store(:custom_event_harvest_cycle, custom_event["report_period_in_seconds"] * 1000)

    error_event = state["data_methods"]["error_event_data"]
    store(:error_event_reservoir_size, error_event["max_samples_stored"])
    store(:error_event_harvest_cycle, error_event["report_period_in_seconds"] * 1000)

    span_event = state["data_methods"]["span_event_data"]
    store(:span_event_reservoir_size, span_event["max_samples_stored"])
    store(:span_event_harvest_cycle, span_event["report_period_in_seconds"] * 1000)

    store(:data_report_period, state["data_report_period"] * 1000)

    store(:apdex_t, state["apdex_t"])

    state
  end

  defp store_agent_run(state) do
    state
  end

  def store(key, value) do
    :ets.insert(__MODULE__, {key, value})
  end

  def lookup(key) do
    Application.get_env(:new_relic_agent, key) ||
      case :ets.lookup(__MODULE__, key) do
        [{^key, value}] -> value
        [] -> nil
      end
  end
end
