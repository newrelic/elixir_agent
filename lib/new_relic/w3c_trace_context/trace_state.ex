defmodule NewRelic.W3CTraceContext.TraceState do
  defstruct [:members]

  defmodule State do
    defstruct [
      :version,
      :parent_type,
      :account_id,
      :app_id,
      :span_id,
      :transaction_id,
      :sampled,
      :priority,
      :timestamp
    ]
  end

  def encode(%__MODULE__{members: members}) do
    members
    |> Enum.map(&encode/1)
    |> Enum.join(",")
  end

  def encode(%{vendor: :new_relic, state: state, trusted_account_key: trusted_account_key}) do
    value =
      [
        state.version,
        state.parent_type |> encode_type(),
        state.account_id,
        state.app_id,
        state.span_id,
        state.transaction_id,
        state.sampled |> encode_sampled(),
        state.priority,
        state.timestamp
      ]
      |> Enum.join("-")

    "#{trusted_account_key}@nr=#{value}"
  end

  def encode(%{vendor: vendor, value: value}) do
    "#{vendor}=#{value}"
  end

  def decode(header) when is_binary(header) do
    members =
      header
      |> String.split(",")
      |> Enum.map(&String.split(&1, "="))
      |> Enum.map(&decode/1)

    %__MODULE__{members: members}
  end

  def decode([vendor, value]) do
    decode(vendor_type(vendor), vendor, value)
  end

  def decode(:new_relic, vendor, value) do
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

    [trusted_account_key, _] = String.split(vendor, "@")

    %{
      vendor: :new_relic,
      value: value,
      trusted_account_key: trusted_account_key,
      # Flatten this:
      state: %__MODULE__.State{
        version: version |> String.to_integer(),
        parent_type: parent_type |> decode_type(),
        account_id: account_id,
        app_id: app_id,
        span_id: span_id,
        transaction_id: transaction_id,
        sampled: sampled |> decode_sampled(),
        priority: priority |> String.to_float(),
        timestamp: timestamp |> String.to_integer()
      }
    }
  end

  def decode(:other, vendor, value) do
    %{vendor: vendor, value: value}
  end

  defp vendor_type(vendor) do
    (String.contains?(vendor, "@nr") && :new_relic) || :other
  end

  defp decode_type("0"), do: "App"
  defp decode_type("1"), do: "Browser"
  defp decode_type("2"), do: "Mobile"

  defp encode_type("App"), do: "0"
  defp encode_type("Browser"), do: "1"
  defp encode_type("Mobile"), do: "2"

  defp decode_sampled("1"), do: true
  defp decode_sampled("0"), do: false

  defp encode_sampled(true), do: "1"
  defp encode_sampled(false), do: "0"
end
