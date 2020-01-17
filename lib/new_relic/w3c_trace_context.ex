defmodule NewRelic.W3CTraceContext do
  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun

  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  def extract(conn) do
    [traceparent_header | _] = Plug.Conn.get_req_header(conn, @w3c_traceparent)
    [tracestate_header | _] = Plug.Conn.get_req_header(conn, @w3c_tracestate)

    traceparent = NewRelic.W3CTraceContext.TraceParent.decode(traceparent_header)
    %{members: members} = NewRelic.W3CTraceContext.TraceState.decode(tracestate_header)

    {[tracestate], others} =
      Enum.split_with(
        members,
        &(&1.vendor == :new_relic &&
            &1.state.trusted_account_key == AgentRun.trusted_account_key())
      )

    # need to store other members for outgoing
    %Context{
      source: {:w3c, others},
      type: tracestate.state.parent_type,
      account_id: tracestate.state.account_id,
      app_id: tracestate.state.app_id,
      parent_id: tracestate.state.transaction_id,
      span_guid: tracestate.state.span_id,
      trace_id: traceparent.trace_id,
      trust_key: tracestate.state.trusted_account_key,
      priority: tracestate.state.priority,
      sampled: tracestate.state.sampled,
      timestamp: tracestate.state.timestamp
    }
  end

  def generate(%{source: source} = context) do
    others =
      case source do
        {:w3c, others} -> others
        _ -> []
      end

    traceparent =
      NewRelic.W3CTraceContext.TraceParent.encode(%NewRelic.W3CTraceContext.TraceParent{
        version: "00",
        trace_id: context.trace_id,
        parent_id: context.span_guid |> String.to_integer(16),
        flags: %{sampled: true}
      })

    state = %NewRelic.W3CTraceContext.TraceState{
      members: [
        %{
          vendor: :new_relic,
          state: %NewRelic.W3CTraceContext.TraceState.State{
            trusted_account_key: context.trust_key,
            version: "0",
            parent_type: context.type,
            account_id: context.account_id,
            app_id: context.app_id,
            span_id: context.span_guid,
            transaction_id: context.parent_id,
            sampled: context.sampled,
            priority: context.priority,
            timestamp: context.timestamp
          }
        }
        | others
      ]
    }

    tracestate = NewRelic.W3CTraceContext.TraceState.encode(state)

    {traceparent, tracestate}
  end
end
