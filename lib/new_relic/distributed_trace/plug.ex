defmodule NewRelic.DistributedTrace.Plug do
  @behaviour Plug
  import Plug.Conn
  require Logger

  # Plug that accepts an incoming DT payload and tracks the DT context

  @moduledoc false

  alias NewRelic.DistributedTrace
  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{private: %{newrelic_dt_instrumented: true}} = conn, _opts) do
    Logger.warn(
      "You have instrumented twice in the same plug! Please `use NewRelic.Transaction` only once."
    )

    conn
  end

  def call(conn, _opts), do: trace(conn, NewRelic.Config.enabled?())

  def trace(conn, false), do: conn

  def trace(conn, true) do
    determine_context(conn)
    |> assign_transaction_guid
    |> report_attributes
    |> convert_to_outbound
    |> DistributedTrace.set_tracing_context()

    conn
    |> put_private(:newrelic_dt_instrumented, true)
    |> register_before_send(&before_send/1)
  end

  defp before_send(conn) do
    DistributedTrace.cleanup_context()
    conn
  end

  defp determine_context(conn) do
    with %Context{} = context <- DistributedTrace.accept_distributed_trace_payload(:http, conn),
         %Context{} = context <- restrict_access(context) do
      context
    else
      _ -> generate_new_context()
    end
  end

  defp assign_transaction_guid(context) do
    Map.put(context, :guid, DistributedTrace.generate_guid())
  end

  defp report_attributes(%Context{parent_id: nil} = context) do
    [
      guid: context.guid,
      traceId: context.guid,
      priority: context.priority,
      sampled: context.sampled
    ]
    |> NewRelic.add_attributes()

    context
  end

  defp report_attributes(context) do
    [
      "parent.type": context.type,
      "parent.app": context.app_id,
      "parent.account": context.account_id,
      "parent.transportType": "http",
      "parent.transportDuration": transport_duration(context.timestamp),
      parentId: context.parent_id,
      parentSpanId: context.span_guid,
      guid: context.guid,
      traceId: context.trace_id,
      priority: context.priority,
      sampled: context.sampled
    ]
    |> NewRelic.add_attributes()

    context
  end

  defp convert_to_outbound(%Context{parent_id: nil} = context) do
    %Context{
      account_id: AgentRun.account_id(),
      app_id: AgentRun.primary_application_id(),
      parent_id: nil,
      trust_key: context.trust_key,
      guid: context.guid,
      trace_id: context.guid,
      priority: context.priority,
      sampled: context.sampled
    }
  end

  defp convert_to_outbound(%Context{} = context) do
    %Context{
      account_id: AgentRun.account_id(),
      app_id: AgentRun.primary_application_id(),
      parent_id: context.guid,
      trust_key: context.trust_key,
      guid: context.guid,
      trace_id: context.trace_id,
      priority: context.priority,
      sampled: context.sampled
    }
  end

  defp generate_new_context() do
    {priority, sampled} = generate_sampling()

    %Context{
      account_id: AgentRun.account_id(),
      app_id: AgentRun.primary_application_id(),
      trust_key: AgentRun.trusted_account_key(),
      priority: priority,
      sampled: sampled
    }
  end

  @doc false
  def restrict_access(context) do
    if (context.trust_key || context.account_id) == AgentRun.trusted_account_key() do
      context
    else
      :restricted
    end
  end

  defp generate_sampling() do
    case {generate_sample?(), generate_priority()} do
      {true, priority} -> {priority + 1, true}
      {false, priority} -> {priority, false}
    end
  end

  defp generate_sample?() do
    NewRelic.DistributedTrace.BackoffSampler.sample?()
  end

  defp generate_priority, do: :rand.uniform() |> Float.round(6)

  defp transport_duration(context_start_time) do
    (System.system_time(:milliseconds) - context_start_time) / 1_000
  end
end
