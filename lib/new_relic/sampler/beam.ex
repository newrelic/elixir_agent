defmodule NewRelic.Sampler.Beam do
  use GenServer
  @kb 1024
  @mb 1024 * 1024

  # Takes samples of the state of the BEAM at an interval

  @moduledoc false

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    # throw away first value
    :cpu_sup.util()

    NewRelic.sample_process()

    if NewRelic.Config.enabled?(),
      do: Process.send_after(self(), :report, NewRelic.Sampler.Reporter.random_offset())

    {:ok, %{previous: take_sample()}}
  end

  def handle_info(:report, state) do
    current_sample = record_sample(state)
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, %{state | previous: current_sample}}
  end

  def handle_call(:report, _from, state) do
    current_sample = record_sample(state)
    {:reply, :ok, %{state | previous: current_sample}}
  end

  def record_sample(state) do
    {current_sample, stats} = collect(state.previous)
    NewRelic.report_sample(:BeamStat, stats)
    NewRelic.report_metric(:memory, mb: stats[:memory_total_mb])
    NewRelic.report_metric(:cpu, utilization: stats[:cpu_utilization])
    current_sample
  end

  defp collect(previous) do
    current_sample = take_sample()
    stats = Map.merge(current_sample, delta(previous, current_sample))
    {current_sample, stats}
  end

  defp take_sample do
    {gcs, _, _} = :erlang.statistics(:garbage_collection)
    {reductions, _} = :erlang.statistics(:reductions)
    {{:input, bytes_in}, {:output, bytes_out}} = :erlang.statistics(:io)
    memory = :erlang.memory()

    %{
      garbage_collections: gcs,
      input_kb: bytes_in / @kb,
      output_kb: bytes_out / @kb,
      reductions: reductions,
      run_queue: :erlang.statistics(:total_run_queue_lengths),
      memory_total_mb: memory[:total] / @mb,
      memory_procs_mb: memory[:processes_used] / @mb,
      memory_ets_mb: memory[:ets] / @mb,
      memory_atom_mb: memory[:atom_used] / @mb,
      memory_binary_mb: memory[:binary] / @mb,
      memory_code_mb: memory[:code] / @mb,
      atom_count: :erlang.system_info(:atom_count),
      ets_count: safe_check(:erlang, :system_info, [:ets_count]),
      port_count: :erlang.system_info(:port_count),
      process_count: :erlang.system_info(:process_count),
      atom_limit: :erlang.system_info(:atom_limit),
      ets_limit: :erlang.system_info(:ets_limit),
      port_limit: :erlang.system_info(:port_limit),
      process_limit: :erlang.system_info(:process_limit),
      schedulers: :erlang.system_info(:schedulers),
      scheduler_utilization: safe_check(:scheduler, :sample, []),
      cpu_count: :erlang.system_info(:logical_processors),
      cpu_utilization: :cpu_sup.util()
    }
  end

  def safe_check(m, f, a) do
    # Some checks only available in OTP 21+
    apply(m, f, a)
  rescue
    _ -> nil
  end

  defp delta(previous, current) do
    %{
      garbage_collections: current.garbage_collections - previous.garbage_collections,
      input_kb: current.input_kb - previous.input_kb,
      output_kb: current.output_kb - previous.output_kb,
      reductions: current.reductions - previous.reductions,
      scheduler_utilization:
        delta(:util, previous.scheduler_utilization, current.scheduler_utilization)
    }
  end

  defp delta(:util, nil, nil), do: nil

  defp delta(:util, previous, current) do
    [{:total, scheduler_utilization, _} | _] = :scheduler.utilization(previous, current)
    scheduler_utilization
  end
end
