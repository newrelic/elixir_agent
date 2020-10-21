defmodule NewRelic.DistributedTrace.W3CTraceContext do
  @moduledoc false

  alias NewRelic.Harvest.Collector.AgentRun
  alias NewRelic.DistributedTrace.Context
  alias __MODULE__.{TraceParent, TraceState}

  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  def extract(headers) do
    with traceparent_header <- Map.get(headers, @w3c_traceparent),
         tracestate_header <- Map.get(headers, @w3c_tracestate),
         %TraceParent{} = traceparent <- TraceParent.decode(traceparent_header),
         %TraceState{} = tracestate <- TraceState.decode(tracestate_header) do
      case TraceState.restrict_access(tracestate) do
        {newrelic, others} ->
          NewRelic.report_metric(:supportability, [:trace_context, :accept, :success])

          %Context{
            source:
              {:w3c,
               %{
                 tracestate: :new_relic,
                 sampled: traceparent.flags.sampled,
                 others: others,
                 span_id: newrelic.span_id,
                 tracing_vendors: Enum.map(others, & &1.key)
               }},
            type: newrelic.parent_type,
            account_id: newrelic.account_id,
            app_id: newrelic.app_id,
            parent_id: newrelic.transaction_id,
            span_guid: traceparent.parent_id,
            trace_id: traceparent.trace_id,
            trust_key: newrelic.trusted_account_key,
            priority: newrelic.priority,
            sampled: newrelic.sampled,
            timestamp: newrelic.timestamp
          }

        others ->
          NewRelic.report_metric(:supportability, [:trace_context, :accept, :success])
          NewRelic.report_metric(:supportability, [:trace_context, :tracestate, :non_new_relic])

          %Context{
            source:
              {:w3c,
               %{
                 tracestate: :non_new_relic,
                 sampled: traceparent.flags.sampled,
                 others: others,
                 tracing_vendors: Enum.map(others, & &1.key)
               }},
            parent_id: traceparent.parent_id,
            span_guid: traceparent.parent_id,
            trace_id: traceparent.trace_id,
            trust_key: AgentRun.trusted_account_key()
          }
      end
    else
      _ ->
        NewRelic.report_metric(:supportability, [:trace_context, :accept, :exception])
        :bad_trace_context
    end
  end

  def generate(%{source: source} = context) do
    {others, traceparent_sampled} =
      case source do
        {:w3c, %{others: others, sampled: sampled}} -> {others, sampled}
        _ -> {[], context.sampled}
      end

    traceparent =
      TraceParent.encode(%TraceParent{
        trace_id: context.trace_id,
        parent_id: context.span_guid,
        flags: %{sampled: traceparent_sampled}
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
