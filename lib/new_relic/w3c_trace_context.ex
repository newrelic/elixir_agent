defmodule NewRelic.W3CTraceContext do
  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace.Context
  alias __MODULE__.{TraceParent, TraceState}

  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  def extract(conn) do
    [traceparent_header | _] = Plug.Conn.get_req_header(conn, @w3c_traceparent)
    [tracestate_header | _] = Plug.Conn.get_req_header(conn, @w3c_tracestate)

    traceparent = TraceParent.decode(traceparent_header)

    tracestate_header
    |> TraceState.decode()
    |> TraceState.newrelic()
    |> case do
      {[], others} ->
        %Context{
          source:
            {:w3c,
             %{
               tracestate: :non_new_relic,
               others: others,
               sampled: traceparent.flags.sampled,
               tracing_vendors: Enum.map(others, & &1.key) |> Enum.join(",")
             }},
          parent_id: traceparent.parent_id,
          span_guid: traceparent.parent_id,
          trace_id: traceparent.trace_id,
          trust_key: Collector.AgentRun.trusted_account_key()
        }

      {[%{value: tracestate}], others} ->
        %Context{
          source:
            {:w3c,
             %{
               tracestate: :new_relic,
               span_id: tracestate.span_id,
               others: others,
               sampled: traceparent.flags.sampled,
               tracing_vendors: Enum.map(others, & &1.key) |> Enum.join(",")
             }},
          type: tracestate.parent_type,
          account_id: tracestate.account_id,
          app_id: tracestate.app_id,
          parent_id: tracestate.transaction_id,
          span_guid: traceparent.parent_id,
          trace_id: traceparent.trace_id,
          trust_key: tracestate.trusted_account_key,
          priority: tracestate.priority,
          sampled: tracestate.sampled,
          timestamp: tracestate.timestamp
        }
    end
  end

  def generate(%{source: source} = context) do
    {others, sampled} =
      case source do
        {:w3c, %{others: others, sampled: sampled}} -> {others, sampled}
        _ -> {[], context.sampled}
      end

    traceparent =
      TraceParent.encode(%TraceParent{
        trace_id: context.trace_id,
        parent_id: context.span_guid,
        flags: %{sampled: sampled}
      })

    tracestate =
      TraceState.encode(%TraceState{
        members: [
          %{
            key: :new_relic,
            value: %TraceState.NewRelicState{
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
