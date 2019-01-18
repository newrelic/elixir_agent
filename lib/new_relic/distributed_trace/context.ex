defmodule NewRelic.DistributedTrace.Context do
  # Struct containing the DT payload context

  @moduledoc false

  @payload_version [0, 1]

  defstruct type: "App",
            version: @payload_version,
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

  def decode(raw_payload) when is_binary(raw_payload) do
    with {:ok, json} <- Base.decode64(raw_payload),
         {:ok, map} <- Jason.decode(json),
         context <- validate(map) do
      NewRelic.report_metric(:supportability, [:dt, :accept, :success])
      context
    else
      error ->
        NewRelic.report_metric(:supportability, [:dt, :accept, :parse_error])
        NewRelic.log(:debug, "Bad DT Payload: #{inspect(error)} #{inspect(raw_payload)}")
        nil
    end
  end

  def validate(%{
        "v" => @payload_version,
        "d" =>
          %{
            "ty" => type,
            "ac" => account_id,
            "ap" => app_id,
            "tr" => trace_id,
            "ti" => timestamp
          } = data
      }) do
    %__MODULE__{
      version: @payload_version,
      type: type,
      account_id: account_id,
      app_id: app_id,
      parent_id: data["tx"],
      span_guid: data["id"],
      trace_id: trace_id,
      trust_key: data["tk"],
      priority: data["pr"],
      sampled: data["sa"] || false,
      timestamp: timestamp
    }
  end

  def validate(_invalid), do: :invalid

  def encode(context, current_span_guid) do
    %{
      "v" => @payload_version,
      "d" =>
        %{
          "ty" => context.type,
          "ac" => context.account_id,
          "ap" => context.app_id,
          "tx" => context.guid,
          "tr" => context.trace_id,
          "pr" => context.priority,
          "sa" => context.sampled,
          "ti" => System.system_time(:millisecond)
        }
        |> maybe_put(:span_guid, "id", context.sampled, current_span_guid)
        |> maybe_put(:trust_key, "tk", context.account_id, context.trust_key)
    }
    |> Jason.encode!()
    |> Base.encode64()
  end

  def maybe_put(data, :span_guid, key, true = _sampled, guid), do: Map.put(data, key, guid)
  def maybe_put(data, :span_guid, _key, false = _sampled, _guid), do: data

  def maybe_put(data, :trust_key, _key, account_id, account_id), do: data
  def maybe_put(data, :trust_key, _key, _account_id, nil), do: data
  def maybe_put(data, :trust_key, key, _account_id, trust_key), do: Map.put(data, key, trust_key)

  def parse_int(nil), do: :error
  def parse_int(field), do: Integer.parse(field)
end
