defmodule NewRelic.DistributedTrace do
  @dt_header "newrelic"

  @moduledoc false

  alias NewRelic.DistributedTrace.{Context, Tracker}
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
    Process.put(:nr_current_span_attrs, attrs)
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

  def set_current_span(mfa: mfa) do
    prev = Process.get(:nr_current_span)
    Process.put(:nr_current_span, mfa)
    prev
  end

  def get_current_span_guid() do
    case Process.get(:nr_current_span) do
      nil -> generate_guid(pid: self())
      mfa -> generate_guid(pid: self(), mfa: mfa)
    end
  end

  def reset_current_span(prev: prev) do
    Process.put(:nr_current_span, prev)
  end

  def generate_guid(), do: :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  def generate_guid(pid: pid), do: encode_guid([pid, node()])
  def generate_guid(pid: pid, mfa: mfa), do: encode_guid([mfa, pid, node()])

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
end
