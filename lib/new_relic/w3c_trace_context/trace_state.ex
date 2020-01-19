defmodule NewRelic.W3CTraceContext.TraceState do
  alias NewRelic.Harvest.Collector.AgentRun

  defstruct [:members]

  defmodule NewRelicState do
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

  def newrelic(%__MODULE__{members: members}) do
    Enum.split_with(
      members,
      &(&1.key == :new_relic &&
          &1.value.trusted_account_key == AgentRun.trusted_account_key())
    )
  end

  def encode(%__MODULE__{members: members}) do
    members
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
        value.priority,
        value.timestamp
      ]
      |> Enum.join("-")

    "#{value.trusted_account_key}@nr=#{encoded_value}"
  end

  def encode(%{key: key, value: value}) do
    "#{key}=#{value}"
  end

  def decode(header) when is_binary(header) do
    members =
      header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "="))
      |> Enum.map(&decode/1)

    %__MODULE__{members: members}
  end

  def decode([key, value]) do
    decode(vendor_type(key), key, value)
  end

  def decode(:new_relic, key, value) do
    [
      version,
      parent_type,
      account_id,
      app_id,
      span_id,
      transaction_id,
      sampled,
      priority,
      timestamp
    ] = String.split(value, "-")

    [trusted_account_key, _] = String.split(key, "@")

    %{
      key: :new_relic,
      value: %__MODULE__.NewRelicState{
        trusted_account_key: trusted_account_key,
        version: version |> String.to_integer(),
        parent_type: parent_type |> decode_type(),
        account_id: account_id,
        app_id: app_id,
        span_id: span_id,
        transaction_id: transaction_id,
        sampled: sampled |> decode_sampled(),
        priority: priority |> decode_priority(),
        timestamp: timestamp |> String.to_integer()
      }
    }
  end

  def decode(:other, key, value) do
    %{key: key, value: value}
  end

  defp vendor_type(key) do
    (String.contains?(key, "@nr") && :new_relic) || :other
  end

  defp decode_type("0"), do: "App"
  defp decode_type("1"), do: "Browser"
  defp decode_type("2"), do: "Mobile"

  defp encode_type("App"), do: "0"
  defp encode_type("Browser"), do: "1"
  defp encode_type("Mobile"), do: "2"

  defp decode_priority(""), do: nil
  defp decode_priority(priority), do: String.to_float(priority)

  defp decode_sampled("1"), do: true
  defp decode_sampled("0"), do: false
  defp decode_sampled(""), do: nil

  defp encode_sampled(true), do: "1"
  defp encode_sampled(false), do: "0"
end
