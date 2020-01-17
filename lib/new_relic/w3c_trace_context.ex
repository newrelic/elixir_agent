defmodule NewRelic.W3CTraceContext do
  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun
  alias __MODULE__.{TraceParent, TraceState}

  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"
  @hex 16

  def extract(conn) do
    [traceparent_header | _] = Plug.Conn.get_req_header(conn, @w3c_traceparent)
    [tracestate_header | _] = Plug.Conn.get_req_header(conn, @w3c_tracestate)

    traceparent = TraceParent.decode(traceparent_header)
    {tracestate, others} = TraceState.decode(tracestate_header) |> TraceState.newrelic()

    %Context{
      source: {:w3c, %{others: others, sampled: traceparent.flags.sampled}},
      type: tracestate.parent_type,
      account_id: tracestate.account_id,
      app_id: tracestate.app_id,
      parent_id: tracestate.transaction_id,
      span_guid: tracestate.span_id,
      trace_id: traceparent.trace_id,
      trust_key: tracestate.trusted_account_key,
      priority: tracestate.priority,
      sampled: tracestate.sampled,
      timestamp: tracestate.timestamp
    }
  end

  def generate(context, current_span_guid) do
    generate(%{context | span_guid: current_span_guid})
  end

  def generate(%{source: source} = context) do
    {others, sampled} =
      case source do
        {:w3c, %{others: others, sampled: sampled}} -> {others, sampled}
        _ -> {[], context.sampled}
      end

    traceparent =
      TraceParent.encode(%TraceParent{
        trace_id: context.trace_id |> String.to_integer(@hex),
        parent_id: context.span_guid |> String.to_integer(@hex),
        flags: %{sampled: sampled}
      })

    tracestate =
      TraceState.encode(%TraceState{
        members: [
          %{
            key: :new_relic,
            value: %TraceState.NewRelic{
              trusted_account_key: context.trust_key,
              parent_type: context.type,
              account_id: context.account_id,
              app_id: context.app_id,
              span_id: context.span_guid,
              transaction_id: context.parent_id,
              sampled: context.sampled,
              priority: context.priority,
              timestamp: System.system_time(:millisecond)
            }
          }
          | others
        ]
      })

    {traceparent, tracestate}
  end
end
