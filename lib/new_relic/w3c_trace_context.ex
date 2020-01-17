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
    %{members: members} = TraceState.decode(tracestate_header)

    {[%{value: tracestate}], others} =
      Enum.split_with(
        members,
        &(&1.key == :new_relic && &1.value.trusted_account_key == AgentRun.trusted_account_key())
      )

    %Context{
      source: {:w3c, others},
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
        parent_id: context.span_guid |> String.to_integer(@hex),
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
