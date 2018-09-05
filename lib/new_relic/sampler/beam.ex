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
    NewRelic.sample_process()
    if NewRelic.Config.enabled?(), do: send(self(), :report)
    {:ok, %{last: take_sample()}}
  end

  def handle_info(:report, state) do
    current_sample = record_sample(state)
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, %{state | last: current_sample}}
  end

  def handle_call(:report, _from, state) do
    current_sample = record_sample(state)
    {:reply, :ok, %{state | last: current_sample}}
  end

  def record_sample(state) do
    {current_sample, stats} = collect(state.last)
    NewRelic.report_sample(:BeamStat, stats)
    current_sample
  end

  defp collect(last) do
    current_sample = take_sample()
    stats = Map.merge(current_sample, delta(last, current_sample))
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
      run_queue: :erlang.statistics(:run_queue),
      process_count: :erlang.system_info(:process_count),
      memory_total_mb: memory[:total] / @mb,
      memory_procs_mb: memory[:processes_used] / @mb,
      memory_ets_mb: memory[:ets] / @mb,
      memory_atom_mb: memory[:atom_used] / @mb
    }
  end

  defp delta(last, current),
    do: %{
      garbage_collections: current.garbage_collections - last.garbage_collections,
      input_kb: current.input_kb - last.input_kb,
      output_kb: current.output_kb - last.output_kb,
      reductions: current.reductions - last.reductions
    }
end
