defmodule NewRelic.DistributedTrace do
  @nr_header "newrelic"
  @w3c_traceparent "traceparent"
  @w3c_tracestate "tracestate"

  @moduledoc false

  alias NewRelic.DistributedTrace.Context
  alias NewRelic.Harvest.Collector.AgentRun
  alias NewRelic.Transaction

  def start(:http, headers) do
    determine_context(:http, headers)
    |> track_transaction(transport_type: "HTTP")
  end

  defp determine_context(:http, headers) do
    case accept_distributed_trace_headers(:http, headers) do
      %Context{} = context -> context
      _ -> generate_new_context()
    end
  end

  def accept_distributed_trace_headers(:http, headers) do
    w3c_headers(headers) || newrelic_header(headers) || :no_payload
  end

  defp w3c_headers(headers) do
    with {:ok, _traceparent} <- Map.fetch(headers, @w3c_traceparent),
         %Context{} = context <- __MODULE__.W3CTraceContext.extract(headers) do
      context
    else
      _ -> false
    end
  end

  defp newrelic_header(headers) do
    with {:ok, trace_payload} <- Map.fetch(headers, @nr_header),
         %Context{} = context <- __MODULE__.NewRelicContext.extract(trace_payload) do
      context
    else
      _ -> false
    end
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

  def generate_new_context() do
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

  def track_transaction(context, transport_type: type) do
    context
    |> assign_transaction_guid()
    |> maybe_generate_sampling()
    |> maybe_generate_trace_id()
    |> report_attributes(transport_type: type)
    |> report_attributes(:w3c)
    |> convert_to_outbound()
    |> set_tracing_context()
  end

  def maybe_generate_sampling(%Context{sampled: nil, priority: nil} = context) do
    {priority, sampled} = generate_sampling()
    %{context | sampled: sampled, priority: priority}
  end

  def maybe_generate_sampling(context), do: context

  def maybe_generate_trace_id(%Context{trace_id: nil} = context) do
    %{context | trace_id: generate_guid(16)}
  end

  def maybe_generate_trace_id(context) do
    context
  end

  def report_attributes(
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

  def report_attributes(
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

  def report_attributes(context, transport_type: type) do
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

  def report_attributes(%{source: {:w3c, w3c}} = context, :w3c) do
    NewRelic.add_attributes(tracingVendors: Enum.join(w3c.tracing_vendors, ","))

    w3c.tracestate == :new_relic &&
      NewRelic.add_attributes(trustedParentId: w3c.span_id)

    context
  end

  def report_attributes(context, :w3c) do
    context
  end

  def convert_to_outbound(%Context{} = context) do
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

  def set_tracing_context(context) do
    Transaction.Sidecar.trace_context(context)
  end

  def get_tracing_context() do
    Transaction.Sidecar.trace_context()
  end

  def set_span(:generic, attrs) do
    Process.put(:nr_current_span_attrs, Enum.into(attrs, %{}))
  end

  def set_span(:http, url: url, method: method, component: component) do
    Process.put(:nr_current_span_attrs, %{url: url, method: method, component: component})
  end

  def set_span(:error, message: message) do
    Process.put(
      :nr_current_span_attrs,
      Map.merge(get_span_attrs(), %{error: true, "error.message": message})
    )
  end

  def set_span(
        :datastore,
        statement: statement,
        instance: instance,
        address: address,
        hostname: hostname,
        component: component
      ) do
    Process.put(:nr_current_span_attrs, %{
      statement: statement,
      instance: instance,
      address: address,
      hostname: hostname,
      component: component
    })
  end

  def get_span_attrs() do
    Process.get(:nr_current_span_attrs) || %{}
  end

  @max_open_span_count Application.get_env(:new_relic, :max_open_span_count, 20)

  def start_span(options) do
    id = Keyword.fetch!(options, :id)
    name = Keyword.fetch!(options, :name)
    path = Keyword.get(options, :path)
    parent_path = Keyword.get(options, :parent_path)

    {_current, parent} =
      set_current_span_with_parent(
        label: {name, path},
        ref: id,
        parent_path: parent_path
      )

    case Process.get(:nr_open_span_count, 0) do
      over when over >= @max_open_span_count ->
        Process.put(:nr_open_span_count, over + 1)

        NewRelic.incr_attributes(skipped_span_count: 1)

      under ->
        Process.put(:nr_open_span_count, under + 1)

        start_time = Keyword.get(options, :start_time, System.system_time())
        attributes = Keyword.get(options, :attributes, []) |> Map.new()

        Process.put({:nr_span, id}, {name, parent, start_time, attributes})
    end

    :ok
  end

  def stop_span(options) do
    id = Keyword.fetch!(options, :id)
    duration = Keyword.fetch!(options, :duration)
    aggregate = Keyword.get(options, :aggregate)

    case Process.get({:nr_span, id}) do
      nil ->
        :no_such_span

      {name, parent, start_time, attributes} ->
        Process.put(:nr_open_span_count, Process.get(:nr_open_span_count) - 1)

        name = Keyword.get(options, :name, name)
        path = Keyword.get(options, :path, name)
        timestamp_us = System.convert_time_unit(start_time, :native, :microsecond)
        duration_us = System.convert_time_unit(duration, :native, :microsecond)
        start_attributes = attributes |> Map.new()
        stop_attributes = Keyword.get(options, :attributes, []) |> Map.new()

        NewRelic.Transaction.Reporter.add_trace_segment(%{
          primary_name:
            "#{name}"
            |> String.trim("&")
            |> String.trim("/3")
            |> String.trim("/2"),
          secondary_name: "#{path}",
          attributes: attributes,
          pid: inspect(self()),
          id: {name, id},
          parent_id: parent || :root,
          start_time: start_time,
          start_time_mono: start_attributes.start_time_mono,
          end_time_mono: System.monotonic_time()
        })

        NewRelic.report_span(
          timestamp_ms: timestamp_us / 1000,
          duration_s: duration_us / 1_000_000,
          name: name,
          edge: [span: {name, id}, parent: parent || :root],
          category: "generic",
          attributes: Map.merge(attributes, stop_attributes)
        )

        if aggregate do
          NewRelic.report_aggregate(
            %{
              :name => aggregate.name,
              aggregate.method_key => name
            },
            %{duration_ms: duration_us / 1000, call_count: 1}
          )
        end
    end

    :ok
  end

  def set_current_span(label: label, ref: ref) do
    current = {label, ref}
    previous_span = Process.get(:nr_current_span)
    previous_span_attrs = Process.get(:nr_current_span_attrs)
    Process.put(:nr_current_span, current)
    {current, previous_span, previous_span_attrs}
  end

  def set_current_span_with_parent(label: label, ref: ref, parent_path: parent_path) do
    {name, path} = label
    current = {name, ref}
    parent_span = Process.get({:spans, parent_path})
    Process.put(:nr_current_span, current)
    Process.put({:spans, path}, current)
    {current, parent_span || :root}
  end

  def get_current_span_guid() do
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

  def assign_transaction_guid(context) do
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
