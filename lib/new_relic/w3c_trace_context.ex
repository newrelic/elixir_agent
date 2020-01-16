defmodule NewRelic.W3CTraceContext do
  alias NewRelic.DistributedTrace.Context

  def extract(_conn) do
    %Context{
      type: "App",
      account_id: nil,
      app_id: nil,
      parent_id: nil,
      guid: nil,
      span_guid: nil,
      trace_id: nil,
      trust_key: nil,
      priority: nil,
      sampled: false,
      timestamp: nil
    }
  end
end
