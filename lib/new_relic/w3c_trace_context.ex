defmodule NewRelic.W3CTraceContext do
  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun
  alias __MODULE__.{TraceParent, TraceState}

  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  def extract(conn) do
    [traceparent_header | _] = Plug.Conn.get_req_header(conn, @w3c_traceparent)
    [tracestate_header | _] = Plug.Conn.get_req_header(conn, @w3c_tracestate)

    traceparent = TraceParent.decode(traceparent_header)
    tracestate = TraceState.decode(tracestate_header)

    {[newrelic], others} =
      Enum.split_with(
        tracestate.members,
        &(&1.key == :new_relic &&
            &1.value.trusted_account_key == AgentRun.trusted_account_key())
      )

    # need to store other members for outgoing
    %Context{
      source: {:w3c, others},
      type: newrelic.value.parent_type,
      account_id: newrelic.value.account_id,
      app_id: newrelic.value.app_id,
      parent_id: newrelic.value.transaction_id,
      span_guid: newrelic.value.span_id,
      trace_id: traceparent.trace_id,
      trust_key: newrelic.value.trusted_account_key,
      priority: newrelic.value.priority,
      sampled: newrelic.value.sampled,
      timestamp: newrelic.value.timestamp
    }
  end

  def generate(%{source: source} = context) do
    others =
      case source do
        {:w3c, others} -> others
        _ -> []
      end

    traceparent =
      TraceParent.encode(%TraceParent{
        version: "00",
        trace_id: context.trace_id,
        parent_id: context.span_guid |> String.to_integer(16),
        flags: %{sampled: true}
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
              timestamp: context.timestamp
            }
          }
          | others
        ]
      })

    {traceparent, tracestate}
  end
end
