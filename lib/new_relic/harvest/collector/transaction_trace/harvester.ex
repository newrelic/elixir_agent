defmodule NewRelic.Harvest.Collector.TransactionTrace.Harvester do
  use GenServer

  @moduledoc false

  alias NewRelic.Harvest
  alias NewRelic.Harvest.Collector
  alias NewRelic.Transaction.Trace

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    {:ok,
     %{
       start_time: System.system_time(),
       start_time_mono: System.monotonic_time(),
       end_time_mono: nil,
       traces_by_name: %{},
       slowest_traces: []
     }}
  end

  # API

  def report_trace(%Trace{} = trace), do: report_trace(trace, min_duration())

  def report_trace(%Trace{duration: duration}, min_duration) when duration < min_duration,
    do: :ignore

  def report_trace(%Trace{} = trace, _min_duration),
    do:
      Collector.TransactionTrace.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.cast({:report, trace})

  def gather_harvest,
    do:
      Collector.TransactionTrace.HarvestCycle
      |> Harvest.HarvestCycle.current_harvester()
      |> GenServer.call(:gather_harvest)

  # Server

  def handle_cast(_late_msg, :completed), do: {:noreply, :completed}

  def handle_cast({:report, trace}, state) do
    state =
      state
      |> store_named_trace(trace, max_named_traces())
      |> store_slow_trace(trace, max_slow_traces())

    {:noreply, state}
  end

  def handle_call(_late_msg, _from, :completed), do: {:reply, :completed, :completed}

  def handle_call(:send_harvest, _from, state) do
    send_harvest(%{state | end_time_mono: System.monotonic_time()})
    {:reply, :ok, :completed}
  end

  def handle_call(:gather_harvest, _from, state) do
    {:reply, build_trace_payload(state), state}
  end

  # Helpers

  def store_named_trace(%{traces_by_name: traces_by_name} = state, trace, max_named_traces),
    do: store_named_trace(state, traces_by_name[trace.metric_name], trace, max_named_traces)

  def store_named_trace(
        %{traces_by_name: traces_by_name} = state,
        named_traces,
        trace,
        max_named_traces
      )
      when is_nil(named_traces) or length(named_traces) < max_named_traces,
      do: %{
        state
        | traces_by_name: Map.update(traces_by_name, trace.metric_name, [trace], &[trace | &1])
      }

  def store_named_trace(state, _named_traces, _trace, _max_named_traces), do: state

  def store_slow_trace(%{slowest_traces: slowest_traces} = state, trace, max_slow_traces)
      when length(slowest_traces) < max_slow_traces,
      do: %{state | slowest_traces: [trace | slowest_traces]}

  def store_slow_trace(
        %{slowest_traces: [%{duration: slowest_duration} | _]} = state,
        %{duration: duration} = trace,
        max_slow_traces
      )
      when duration > slowest_duration,
      do: %{state | slowest_traces: Enum.take([trace | state.slowest_traces], max_slow_traces)}

  def store_slow_trace(state, _trace, _max_slow_traces), do: state

  defp send_harvest(state) do
    traces = build_trace_payload(state)
    Collector.Protocol.transaction_trace([Collector.AgentRun.agent_run_id(), traces])
    log_harvest(length(traces))
  end

  defp log_harvest(harvest_size) do
    NewRelic.report_metric({:supportability, "TransactionTraceData"}, harvest_size: harvest_size)
    NewRelic.log(:debug, "Completed Transaction Trace harvest - size: #{harvest_size}")
  end

  defp build_trace_payload(state), do: state |> collect_traces |> Trace.format_traces()

  defp collect_traces(%{slowest_traces: slowest_traces, traces_by_name: traces_by_name}),
    do: (slowest_traces ++ Map.values(traces_by_name)) |> List.flatten() |> Enum.uniq()

  defp min_duration,
    do: Application.get_env(:new_relic_agent, :transaction_trace_min_duration, 50)

  defp max_named_traces,
    do: Application.get_env(:new_relic_agent, :transaction_trace_max_named_traces, 2)

  defp max_slow_traces,
    do: Application.get_env(:new_relic_agent, :transaction_trace_max_slow_traces, 5)
end
