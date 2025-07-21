defmodule NewRelic.DistributedTrace do
  @nr_header "newrelic"
  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  @moduledoc false

  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun
  alias NewRelic.Transaction

  def start(type, headers \\ %{})

  def start(:http, headers) do
    if NewRelic.Config.feature?(:distributed_tracing) do
      determine_context(headers)
      |> track_transaction(transport_type: "HTTP")
    end

    :ok
  end

  def start(:other, headers) do
    if NewRelic.Config.feature?(:distributed_tracing) do
      determine_context(headers)
      |> track_transaction(transport_type: "Other")
    end

    :ok
  end

  defp determine_context(headers) do
    case accept_distributed_trace_headers(headers) do
      %Context{} = context -> context
      _ -> generate_new_context()
    end
  end

  defp accept_distributed_trace_headers(headers) do
    w3c_headers(headers) || newrelic_header(headers) || :no_payload
  end

  defp w3c_headers(headers) do
    with {:ok, traceparent} when is_binary(traceparent) <- Map.fetch(headers, @w3c_traceparent),
         %Context{} = context <- __MODULE__.W3CTraceContext.extract(headers) do
      context
    else
      _ -> false
    end
  end

  defp newrelic_header(headers) do
    with {:ok, trace_payload} when is_binary(trace_payload) <- Map.fetch(headers, @nr_header),
         %Context{} = context <- __MODULE__.NewRelicContext.extract(trace_payload) do
      context
    else
      _ -> false
    end
  end

  def distributed_trace_headers(:other) do
    distributed_trace_headers(:http) |> Map.new()
  end

  def distributed_trace_headers(:http) do
    case get_tracing_context() do
      nil ->
        []

      context ->
        context = %{
          context
          | span_guid: get_current_span_guid(),
            timestamp: System.system_time(:millisecond)
        }

        nr_header = NewRelic.DistributedTrace.NewRelicContext.generate(context)
        {traceparent, tracestate} = NewRelic.DistributedTrace.W3CTraceContext.generate(context)

        [
          {@nr_header, nr_header},
          {@w3c_traceparent, traceparent},
          {@w3c_tracestate, tracestate}
        ]
    end
  end

  # Danger:
  # This function can heavily skew sampling if used on high throughput
  # transactions, and can also lead to over sampling / rejected data
  def prioritize_tracing do
    case get_tracing_context() do
      nil ->
        :ignore

      %{sampled: true} ->
        :ignore

      %{sampled: false} = context ->
        if NewRelic.DistributedTrace.BackoffSampler.priority_sample?() do
          context = %{context | sampled: true, priority: context.priority + 1}
          NewRelic.add_attributes(sampled: true, priority: context.priority)
          set_tracing_context(context)
        end

        :ok
    end
  end

  defp generate_new_context() do
    {priority, sampled} = generate_sampling()

    %Context{
      source: :new,
      account_id: AgentRun.account_id(),
      app_id: AgentRun.primary_application_id(),
      trust_key: AgentRun.trusted_account_key(),
      priority: priority,
      sampled: sampled
    }
  end

  defp track_transaction(context, transport_type: type) do
    context
    |> assign_transaction_guid()
    |> maybe_generate_sampling()
    |> maybe_generate_trace_id()
    |> report_attributes(transport_type: type)
    |> report_attributes(:w3c)
    |> convert_to_outbound()
    |> set_tracing_context()
  end

  defp maybe_generate_sampling(%Context{sampled: nil, priority: nil} = context) do
    {priority, sampled} = generate_sampling()
    %{context | sampled: sampled, priority: priority}
  end

  defp maybe_generate_sampling(context), do: context

  defp maybe_generate_trace_id(%Context{trace_id: nil} = context) do
    %{context | trace_id: generate_guid(16)}
  end

  defp maybe_generate_trace_id(context) do
    context
  end

  defp report_attributes(
         %{source: {:w3c, %{tracestate: :non_new_relic}}} = context,
         transport_type: type
       ) do
    [
      "parent.transportType": type,
      guid: context.trace_id,
      traceId: context.trace_id,
      priority: context.priority,
      sampled: context.sampled,
      parentId: context.parent_id,
      parentSpanId: context.span_guid
    ]
    |> NewRelic.add_attributes()

    context
  end

  defp report_attributes(
         %Context{
           parent_id: nil,
           span_guid: nil
         } = context,
         transport_type: _type
       ) do
    [
      guid: context.guid,
      traceId: context.trace_id,
      priority: context.priority,
      sampled: context.sampled
    ]
    |> NewRelic.add_attributes()

    context
  end

  defp report_attributes(context, transport_type: type) do
    [
      "parent.type": context.type,
      "parent.app": context.app_id,
      "parent.account": context.account_id,
      "parent.transportType": type,
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

  defp report_attributes(%{source: {:w3c, w3c}} = context, :w3c) do
    NewRelic.add_attributes(tracingVendors: Enum.join(w3c.tracing_vendors, ","))

    w3c.tracestate == :new_relic &&
      NewRelic.add_attributes(trustedParentId: w3c.span_id)

    context
  end

  defp report_attributes(context, :w3c) do
    context
  end

  defp convert_to_outbound(%Context{} = context) do
    %Context{
      source: context.source,
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

  defp set_tracing_context(context) do
    Transaction.Sidecar.trace_context(context)
  end

  def get_tracing_context() do
    Transaction.Sidecar.trace_context()
  end

  def set_span(:generic, attrs) do
    add_span_attributes(Map.new(attrs))
  end

  def set_span(:http, url: url, method: method, component: component) do
    add_span_attributes(%{url: url, method: method, component: component})
  end

  def set_span(:error, message: message) do
    add_span_attributes(%{error: true, "error.message": message})
  end

  def set_span(:datastore,
        statement: statement,
        instance: instance,
        address: address,
        hostname: hostname,
        component: component
      ) do
    add_span_attributes(%{
      statement: statement,
      instance: instance,
      address: address,
      hostname: hostname,
      component: component
    })
  end

  def add_span_attributes(attrs) do
    Process.put(
      :nr_current_span_attrs,
      Map.merge(get_span_attrs(), Map.new(attrs))
    )

    :ok
  end

  def get_span_attrs() do
    Process.get(:nr_current_span_attrs) || %{}
  end

  def set_current_span(label: label, ref: ref) do
    current = {label, ref}
    previous_span = Process.delete(:nr_current_span)
    previous_span_attrs = Process.delete(:nr_current_span_attrs)
    Process.put(:nr_current_span, current)
    {current, previous_span, previous_span_attrs}
  end

  defp get_current_span_guid() do
    case Process.get(:nr_current_span) do
      nil -> generate_guid(pid: self())
      {label, ref} -> generate_guid(pid: self(), label: label, ref: ref)
    end
  end

  def read_current_span() do
    Process.get(:nr_current_span)
  end

  def reset_span(previous_span: previous_span, previous_span_attrs: previous_span_attrs) do
    Process.put(:nr_current_span, previous_span)
    Process.put(:nr_current_span_attrs, previous_span_attrs)
  end

  defp generate_sampling() do
    case {generate_sample?(), generate_priority()} do
      {true, priority} -> {priority + 1.0, true}
      {false, priority} -> {priority, false}
    end
  end

  defp generate_sample?() do
    NewRelic.DistributedTrace.BackoffSampler.sample?()
  end

  defp generate_priority do
    :rand.uniform() |> Float.round(6)
  end

  defp assign_transaction_guid(context) do
    Map.put(context, :guid, generate_guid())
  end

  def generate_guid(), do: :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  def generate_guid(16), do: :crypto.strong_rand_bytes(16) |> Base.encode16() |> String.downcase()
  def generate_guid(pid: pid), do: encode_guid([pid, node()])
  def generate_guid(pid: pid, label: label, ref: ref), do: encode_guid([label, ref, pid, node()])

  def encode_guid(segments) when is_list(segments) do
    segments
    |> Enum.map(&encode_guid/1)
    |> Enum.join("")
    |> String.pad_trailing(16, "0")
  end

  def encode_guid(term) do
    term
    |> :erlang.phash2()
    |> Integer.to_charlist(16)
    |> to_string()
    |> String.slice(0..3)
    |> String.downcase()
  end

  defp transport_duration(context_start_time) do
    (System.system_time(:millisecond) - context_start_time) / 1_000
  end
end
