defmodule NewRelic.DistributedTrace.Context do
  @moduledoc false

  defstruct type: "App",
            source: nil,
            version: nil,
            account_id: nil,
            app_id: nil,
            parent_id: nil,
            guid: nil,
            span_guid: nil,
            trace_id: nil,
            trust_key: nil,
            priority: nil,
            sampled: nil,
            timestamp: nil
end
