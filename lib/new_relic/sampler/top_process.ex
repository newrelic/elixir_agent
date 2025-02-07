defmodule NewRelic.Sampler.TopProcess do
  use GenServer

  # Track and sample the top processes by:
  # * memory usage
  # * message queue length

  @moduledoc false

  alias NewRelic.Util.PriorityQueue, as: PQ

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()

    if NewRelic.Config.enabled?(),
      do: Process.send_after(self(), :sample, NewRelic.Sampler.Reporter.random_sample_offset())

    {:ok, :reset}
  end

  def handle_info(:sample, :reset) do
    top_procs = detect_top_processes()
    Process.send_after(self(), :report, NewRelic.Sampler.Reporter.sample_cycle())
    {:noreply, top_procs}
  end

  @kb 1024
  def handle_info(:report, top_procs) do
    Enum.each(top_procs, &report_sample/1)
    send(self(), :sample)
    {:noreply, :reset}
  end

  def detect_top_processes() do
    {mem_pq, msg_pq} =
      Process.list()
      |> Enum.reduce({PQ.new(), PQ.new()}, &measure_and_insert/2)

    (PQ.values(mem_pq) ++ PQ.values(msg_pq))
    |> Enum.uniq_by(&elem(&1, 0))
  end

  @size 5
  defp measure_and_insert(pid, {mem_pq, msg_pq}) do
    case Process.info(pid, [:memory, :message_queue_len, :registered_name, :reductions]) do
      [memory: mem, message_queue_len: msg, registered_name: _, reductions: _] = info ->
        mem_pq = PQ.insert(mem_pq, @size, mem, {pid, info})
        msg_pq = if msg > 0, do: PQ.insert(msg_pq, @size, msg, {pid, info}), else: msg_pq
        {mem_pq, msg_pq}

      nil ->
        {mem_pq, msg_pq}
    end
  end

  defp report_sample({pid, info}) do
    case Process.info(pid, :reductions) do
      {:reductions, current_reductions} ->
        NewRelic.report_sample(:ProcessSample, %{
          pid: inspect(pid),
          memory_kb: info[:memory] / @kb,
          message_queue_length: info[:message_queue_len],
          name: parse(:name, pid, info[:registered_name]),
          reductions: current_reductions - info[:reductions]
        })

      nil ->
        :ignore
    end
  end

  defp parse(:name, pid, []) do
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary),
         {m, f, a} <- Keyword.get(dictionary, :"$initial_call") do
      "#{inspect(m)}.#{f}/#{a}"
    else
      _ -> inspect(pid)
    end
  end

  defp parse(:name, _pid, name), do: inspect(name)
end
