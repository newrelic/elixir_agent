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

    {tracestate, others} =
      Enum.split_with(
        members,
        &(&1.vendor == :new_relic &&
            &1.trusted_account_key == AgentRun.trusted_account_key())
      )

    # need to store other members for outgoing
    %Context{
      source: {:w3c, others},
      type: tracestate.state.parent_type,
      account_id: tracestate.state.account_id,
      app_id: tracestate.state.app_id,
      parent_id: tracestate.state.transaction_id,
      span_guid: traceparent.parent_id,
      trace_id: traceparent.trace_id,
      trust_key: tracestate.trusted_account_key,
      priority: tracestate.state.priority,
      sampled: tracestate.state.sampled,
      timestamp: tracestate.state.timestamp
    }
  end
end
