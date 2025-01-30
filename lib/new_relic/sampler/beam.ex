defmodule NewRelic.Sampler.Beam do
  use GenServer
  @kb 1024
  @mb 1024 * 1024

  # Takes samples of the state of the BEAM at an interval

  @moduledoc false

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    :erlang.system_flag(:scheduler_wall_time, true)

    # throw away first value
    NewRelic.OsMon.util()
    :erlang.statistics(:scheduler_wall_time)

    NewRelic.sample_process()

    if NewRelic.Config.enabled?(),
      do: Process.send_after(self(), :report, NewRelic.Sampler.Reporter.random_sample_offset())

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

  defp record_sample(state) do
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
      ets_count: :erlang.system_info(:ets_count),
      port_count: :erlang.system_info(:port_count),
      process_count: :erlang.system_info(:process_count),
      atom_limit: :erlang.system_info(:atom_limit),
      ets_limit: :erlang.system_info(:ets_limit),
      port_limit: :erlang.system_info(:port_limit),
      process_limit: :erlang.system_info(:process_limit),
      schedulers: :erlang.system_info(:schedulers),
      scheduler_utilization: :erlang.statistics(:scheduler_wall_time) |> Enum.sort(),
      cpu_count: :erlang.system_info(:logical_processors),
      cpu_utilization: NewRelic.OsMon.util()
    }
  end

  defp delta(previous, current) do
    %{
      garbage_collections: current.garbage_collections - previous.garbage_collections,
      input_kb: current.input_kb - previous.input_kb,
      output_kb: current.output_kb - previous.output_kb,
      reductions: current.reductions - previous.reductions,
      scheduler_utilization: delta(:util, previous.scheduler_utilization, current.scheduler_utilization)
    }
  end

  defp delta(:util, previous, current) do
    {_, {active, total}} =
      Enum.zip(previous, current)
      |> Enum.map_reduce({0, 0}, fn
        {{n, a0, t0}, {n, a1, t1}}, {acc_a, acc_t} ->
          {{n, a1 - a0, t1 - t0}, {acc_a + (a1 - a0), acc_t + (t1 - t0)}}
      end)

    safe_div(active, total)
  end

  defp safe_div(a, b) do
    a / b
  rescue
    ArithmeticError -> 0.0
  end
end
