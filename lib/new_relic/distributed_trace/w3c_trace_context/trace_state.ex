defmodule NewRelic.DistributedTrace.W3CTraceContext.TraceState do
  @moduledoc false

  # https://w3c.github.io/trace-context/#tracestate-header

  alias NewRelic.Harvest.Collector.AgentRun

  defstruct [:members]

  defmodule NewRelicState do
    @moduledoc false

    defstruct version: "0",
              trusted_account_key: nil,
              parent_type: nil,
              account_id: nil,
              app_id: nil,
              span_id: nil,
              transaction_id: nil,
              sampled: nil,
              priority: nil,
              timestamp: nil
  end

  def encode(%__MODULE__{members: members}) do
    members
    |> Enum.take(32)
    |> Enum.map(&encode/1)
    |> Enum.join(",")
  end

  def encode(%{key: :new_relic, value: value}) do
    encoded_value =
      [
        value.version,
        value.parent_type |> encode_type(),
        value.account_id,
        value.app_id,
        value.span_id,
        value.transaction_id,
        value.sampled |> encode_sampled(),
        value.priority |> encode_priority(),
        value.timestamp
      ]
      |> Enum.join("-")

    "#{value.trusted_account_key}@nr=#{encoded_value}"
  end

  def encode(%{key: key, value: value}) do
    "#{key}=#{value}"
  end

  def decode(nil), do: %__MODULE__{members: []}

  def decode(header) when is_binary(header) do
    members =
      header
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.split(&1, "="))
      |> Enum.reject(&(&1 == [""]))

    %__MODULE__{members: validate(members)}
  end

  def restrict_access(%__MODULE__{members: members}) do
    members
    |> Enum.split_with(&matching_new_relic_state?/1)
    |> case do
      {[%{value: new_relic}], others} -> {new_relic, others}
      {_, others} -> others
    end
  end

  defp matching_new_relic_state?(context) do
    context.key == :new_relic &&
      context.value.trusted_account_key == AgentRun.trusted_account_key()
  end

  defp validate(members) do
    case valid_members?(members) do
      true -> Enum.flat_map(members, &decode_member/1)
      false -> []
    end
  end

  defp valid_members?(members) do
    Enum.all?(members, &valid_member?/1) &&
      no_duplicate_keys(members) &&
      length(members) <= 32
  end

  @key_wo_vendor ~r/^[0-9a-z][_0-9a-z\-\*\/]{0,255}$/
  @key_with_vendor ~r/^[0-9a-z][_0-9a-z\-\*\/]{0,240}@[0-9a-z][_0-9a-z\-\*\/]{0,13}$/
  @value ~r/^([\x20-\x2b\x2d-\x3c\x3e-\x7e]{0,255}[\x21-\x2b\x2d-\x3c\x3e-\x7e])$/
  defp valid_member?([key, value]) do
    valid_key? = Regex.match?(@key_wo_vendor, key) || Regex.match?(@key_with_vendor, key)
    valid_value? = Regex.match?(@value, value)

    valid_key? && valid_value?
  end

  defp valid_member?(_) do
    false
  end

  defp no_duplicate_keys(members) do
    keys = Enum.map(members, &List.first/1)
    duplicates? = length(keys) != length(Enum.uniq(keys))

    !duplicates?
  end

  defp decode_member([key, value]) do
    decode_member(vendor_type(key), key, value)
  end

  @version_0 "0-"
  @version_0_range 1..8

  defp decode_member(:new_relic, key, @version_0 <> _ = value) do
    with [
           "0",
           parent_type,
           account_id,
           app_id,
           span_id,
           transaction_id,
           sampled,
           priority,
           timestamp
         ] <- String.split(value, "-"),
         {sampled, priority} <-
           decode_sampled_priority(sampled, priority),
         [
           trusted_account_key,
           _
         ] <- String.split(key, "@") do
      [
        %{
          key: :new_relic,
          value: %__MODULE__.NewRelicState{
            trusted_account_key: trusted_account_key,
            version: 0,
            parent_type: parent_type |> decode_type(),
            account_id: account_id,
            app_id: app_id,
            span_id: span_id,
            transaction_id: transaction_id,
            sampled: sampled,
            priority: priority,
            timestamp: timestamp |> String.to_integer()
          }
        }
      ]
    else
      _ ->
        NewRelic.report_metric(:supportability, [:trace_context, :tracestate, :invalid])
        NewRelic.log(:debug, "Bad W3C NR tracestate: `#{key}`: `#{value}`")
        []
    end
  end

  # Future versions can have more elements, but meaning of existing fields won't change
  defp decode_member(:new_relic, key, future_value) do
    version_0_value =
      future_value
      |> String.split("-")
      |> Enum.slice(@version_0_range)
      |> Enum.join("-")

    decode_member(:new_relic, key, @version_0 <> version_0_value)
  end

  defp decode_member(:other, key, value) do
    [
      %{key: key, value: value}
    ]
  end

  defp vendor_type(key) do
    if String.contains?(key, "@nr"), do: :new_relic, else: :other
  end

  defp decode_type("0"), do: "App"
  defp decode_type("1"), do: "Browser"
  defp decode_type("2"), do: "Mobile"

  defp encode_type("App"), do: "0"
  defp encode_type("Browser"), do: "1"
  defp encode_type("Mobile"), do: "2"

  defp decode_sampled_priority("", ""), do: {nil, nil}
  defp decode_sampled_priority("", _), do: :invalid
  defp decode_sampled_priority(_, ""), do: :invalid

  defp decode_sampled_priority(sampled, priority) do
    {decode_sampled(sampled), decode_priority(priority)}
  end

  defp decode_priority(""), do: nil
  defp decode_priority(priority), do: String.to_float(priority)

  defp encode_priority(nil), do: ""

  defp encode_priority(priority) when is_integer(priority),
    do: encode_priority(priority / 1)

  defp encode_priority(priority) when is_float(priority),
    do: priority |> :erlang.float_to_binary([:compact, decimals: 6])

  defp decode_sampled("1"), do: true
  defp decode_sampled("0"), do: false
  defp decode_sampled(""), do: nil

  defp encode_sampled(true), do: "1"
  defp encode_sampled(false), do: "0"
  defp encode_sampled(nil), do: ""
end
