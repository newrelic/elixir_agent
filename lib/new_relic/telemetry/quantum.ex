defmodule NewRelic.Telemetry.Quantum do
  @moduledoc """
  Provides `Quantum` instrumentation via `telemetry`.

  We automatically gather:

  * Transaction metrics and events
  * Transaction Traces
  * Distributed Traces

  You can opt-out of this instrumentation via configuration. See `NewRelic.Config` for details.

  ----

  To prevent reporting an individual transaction:

  ```elixir
  NewRelic.ignore_transaction()
  ```

  ----

  Inside a Transaction, the agent will track work across processes that are spawned and linked.
  You can signal to the agent not to track work done inside a spawned process, which will
  exclude it from the current Transaction.

  To exclude a process from the Transaction:

  ```elixir
  Task.async(fn ->
    NewRelic.exclude_from_transaction()
    Work.wont_be_tracked()
  end)
  ```
  """
  use GenServer

  alias NewRelic.DistributedTrace
  alias NewRelic.Transaction

  @doc false
  def start_link(_) do
    config = %{
      enabled?: NewRelic.Config.feature?(:quantum_instrumentation),
      handler_id: {:new_relic, :quantum}
    }

    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @quantum_job_start [:quantum, :job, :start]
  @quantum_job_stop [:quantum, :job, :stop]
  @quantum_job_exception [:quantum, :job, :exception]

  @quantum_job_events [
    @quantum_job_start,
    @quantum_job_stop,
    @quantum_job_exception
  ]

  @doc false
  def init(%{enabled?: false}), do: :ignore

  def init(%{enabled?: true} = config) do
    :telemetry.attach_many(
      config.handler_id,
      @quantum_job_events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(
        @quantum_job_start,
        %{system_time: system_time},
        meta,
        _config
      ) do
    Transaction.Reporter.start_transaction(:other)

    if NewRelic.Config.enabled?() do
      DistributedTrace.generate_new_context()
      |> DistributedTrace.track_transaction(transport_type: "Other")
    end

    add_start_attrs(meta, system_time)
  end

  def handle_event(
        @quantum_job_stop,
        %{duration: duration} = meas,
        meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)

    Transaction.Reporter.stop_transaction(:other)
  end

  def handle_event(
        @quantum_job_exception,
        %{duration: duration} = meas,
        %{kind: kind} = meta,
        _config
      ) do
    add_stop_attrs(meas, meta, duration)
    {reason, stack} = reason_and_stack(meta)

    Transaction.Reporter.fail(%{kind: kind, reason: reason, stack: stack})
    Transaction.Reporter.stop_transaction(:other)
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp add_start_attrs(meta, system_time) do
    [
      pid: inspect(self()),
      system_time: system_time,
      other_transaction_name: quantum_name(meta),
      "quantum.scheduler": meta.scheduler |> inspect(),
      "quantum.job_name":
        case meta.job.name do
          name when is_atom(name) -> to_string(name)
          name -> inspect(name)
        end,
      "quantum.job_schedule": meta.job.schedule |> inspect(),
      "quantum.job_timezone": meta.job.timezone |> to_string()
    ]
    |> NewRelic.add_attributes()
  end

  @kb 1024
  defp add_stop_attrs(_meas, _meta, duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      memory_kb: info[:memory] / @kb,
      reductions: info[:reductions]
    ]
    |> NewRelic.add_attributes()
  end

  defp reason_and_stack(%{reason: %{__exception__: true} = reason, stacktrace: stack}) do
    {reason, stack}
  end

  defp reason_and_stack(%{reason: {{reason, stack}, _init_call}}) do
    {reason, stack}
  end

  defp reason_and_stack(%{reason: {reason, _init_call}}) do
    {reason, []}
  end

  defp reason_and_stack(unexpected_oban_exception) do
    NewRelic.log(:debug, "unexpected_quantum_exception: #{inspect(unexpected_oban_exception)}")
    {:unexpected_quantum_exception, []}
  end

  defp quantum_name(%{scheduler: scheduler, job: %{name: name}}) when is_atom(name) do
    "/Quantum/#{inspect(scheduler)}/#{name}"
  end

  defp quantum_name(%{scheduler: scheduler, job: %{task: {module, function, _args}}}) do
    "/Quantum/#{inspect(scheduler)}/#{inspect(module)}/#{function}"
  end

  defp quantum_name(%{scheduler: scheduler}) do
    "/Quantum/#{inspect(scheduler)}/Unknown"
  end
end
