defmodule NewRelic.DistributedTrace.W3CTraceContext.TraceParent do
  @moduledoc false

  # https://w3c.github.io/trace-context/#traceparent-header

  defstruct version: "00",
            trace_id: nil,
            parent_id: nil,
            flags: nil

  @version 2
  @trace_id 32
  @parent_id 16
  @flags 2

  def decode(<<"ff", "-", _::binary>>),
    do: invalid()

  def decode(<<_::binary-size(@version), "-", "00000000000000000000000000000000", _::binary>>),
    do: invalid()

  def decode(<<_::binary-size(@version), "-", _::binary-size(@trace_id), "-", "0000000000000000", _::binary>>),
    do: invalid()

  def decode(
        <<version::binary-size(@version), "-", trace_id::binary-size(@trace_id), "-",
          parent_id::binary-size(@parent_id), "-", flags::binary-size(@flags)>>
      ) do
    validate(
      [version, trace_id, parent_id, flags],
      %__MODULE__{
        version: version,
        trace_id: trace_id,
        parent_id: parent_id,
        flags: %{sampled: flags == "01"}
      }
    )
  end

  # Future versions can be longer
  def decode(
        <<version::binary-size(@version), "-", trace_id::binary-size(@trace_id), "-",
          parent_id::binary-size(@parent_id), "-", flags::binary-size(@flags), "-", _::binary>>
      )
      when version != "00" do
    validate(
      [version, trace_id, parent_id, flags],
      %__MODULE__{
        version: version,
        trace_id: trace_id,
        parent_id: parent_id,
        flags: %{sampled: flags == "01"}
      }
    )
  end

  def decode(_),
    do: invalid()

  def encode(%__MODULE__{
        version: _version,
        trace_id: trace_id,
        parent_id: parent_id,
        flags: %{
          sampled: sampled
        }
      }) do
    [
      "00",
      String.pad_leading(trace_id, @trace_id, "0") |> String.downcase(),
      String.pad_leading(parent_id, @parent_id, "0") |> String.downcase(),
      (sampled && "01") || "00"
    ]
    |> Enum.join("-")
  end

  defp invalid() do
    NewRelic.report_metric(:supportability, [:trace_context, :traceparent, :invalid])
    :invalid
  end

  defp validate(values, context) do
    case Enum.all?(values, &valid?/1) do
      true -> context
      false -> :invalid
    end
  end

  defp valid?(value),
    do: Base.decode16(value, case: :mixed) != :error
end
