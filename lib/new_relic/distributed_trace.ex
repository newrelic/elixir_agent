defmodule NewRelic.DistributedTrace do
  @dt_header "newrelic"

  @moduledoc false

  alias NewRelic.DistributedTrace.{Context, Tracker}
  alias NewRelic.Harvest.Collector.AgentRun
  alias NewRelic.Transaction

  def accept_distributed_trace_payload(:http, conn) do
    case Plug.Conn.get_req_header(conn, @dt_header) do
      [trace_payload | _] ->
        trace_payload
        |> Context.decode()

      [] ->
        :no_payload
    end
  end

  def create_distributed_trace_payload(:http) do
    case get_tracing_context() do
      nil -> []
      context -> [{@dt_header, Context.encode(context, get_current_span_guid())}]
    end
  end

  def generate_new_context() do
    {priority, sampled} = generate_sampling()

    %Context{
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
    |> report_attributes(transport_type: type)
    |> convert_to_outbound()
    |> set_tracing_context()
  end

  def report_attributes(
        %Context{parent_id: nil} = context,
        transport_type: _type
      ) do
    [
      guid: context.guid,
      traceId: context.guid,
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

  def convert_to_outbound(%Context{parent_id: nil} = context) do
    %Context{
      account_id: AgentRun.account_id(),
      app_id: AgentRun.primary_application_id(),
      parent_id: nil,
      trust_key: context.trust_key,
      guid: context.guid,
      trace_id: context.guid,
      priority: context.priority,
      sampled: context.sampled
    }
  end

  def convert_to_outbound(%Context{} = context) do
    %Context{
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
    Tracker.store(self(), context: context)
  end

  def cleanup_context() do
    Tracker.cleanup(self())
  end

  def get_tracing_context() do
    if Transaction.Reporter.tracking?(self()) do
      self()
      |> Transaction.Reporter.root()
      |> Tracker.fetch()
    end
  end

  def set_span(:generic, attrs) do
    Process.put(:nr_current_span_attrs, Enum.into(attrs, %{}))
  end

  def set_span(:http, url: url, method: method, component: component) do
    Process.put(:nr_current_span_attrs, %{url: url, method: method, component: component})
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

  def set_current_span(label: label, ref: ref) do
    current = {label, ref}
    previous_span = Process.get(:nr_current_span)
    previous_span_attrs = Process.get(:nr_current_span_attrs)
    Process.put(:nr_current_span, current)
    {current, previous_span, previous_span_attrs}
  end

  def get_current_span_guid() do
    case Process.get(:nr_current_span) do
      nil -> generate_guid(pid: self())
      {label, ref} -> generate_guid(pid: self(), label: label, ref: ref)
    end
  end

  def reset_span(previous_span: previous_span, previous_span_attrs: previous_span_attrs) do
    Process.put(:nr_current_span, previous_span)
    Process.put(:nr_current_span_attrs, previous_span_attrs)
  end

  defp generate_sampling() do
    case {generate_sample?(), generate_priority()} do
      {true, priority} -> {priority + 1, true}
      {false, priority} -> {priority, false}
    end
  end

  defp generate_sample?() do
    NewRelic.DistributedTrace.BackoffSampler.sample?()
  end

  defp generate_priority, do: :rand.uniform() |> Float.round(6)

  def assign_transaction_guid(context) do
    Map.put(context, :guid, generate_guid())
  end

  def generate_guid(), do: :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
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
    |> String.slice(0..4)
    |> String.downcase()
  end

  defp transport_duration(context_start_time) do
    (System.system_time(:millisecond) - context_start_time) / 1_000
  end
end
