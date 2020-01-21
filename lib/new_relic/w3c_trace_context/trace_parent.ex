defmodule NewRelic.W3CTraceContext.TraceParent do
  defstruct version: "00",
            trace_id: nil,
            parent_id: nil,
            flags: nil

  use Bitwise

  @version 2
  @trace_id 32
  @parent_id 16
  @flags 2

  def decode(<<"ff", "-", _::binary>>),
    do: :invalid

  def decode(<<_::binary-size(@version), "-", "00000000000000000000000000000000", _::binary>>),
    do: :invalid

  def decode(
        <<_::binary-size(@version), "-", _::binary-size(@trace_id), "-", "0000000000000000",
          _::binary>>
      ),
      do: :invalid

  def decode(
        <<version::binary-size(@version), "-", trace_id::binary-size(@trace_id), "-",
          parent_id::binary-size(@parent_id), "-", flags::binary-size(@flags), rest::binary>>
      ) do
    invalid_version = :error == Base.decode16(version, case: :mixed)
    invalid_trace_id = :error == Base.decode16(trace_id, case: :mixed)
    invalid_parent_id = :error == Base.decode16(parent_id, case: :mixed)
    invalid_flags = :error == Base.decode16(flags, case: :mixed)

    valid_rest =
      case version do
        "00" -> rest == ""
        _ -> String.starts_with?(rest, "-") || rest == ""
      end

    IO.inspect({:rest, rest})

    valid? =
      !invalid_version &&
        !invalid_trace_id && !invalid_parent_id && !invalid_flags && valid_rest

    if valid? do
      %__MODULE__{
        version: version,
        trace_id: trace_id,
        parent_id: parent_id,
        flags: %{
          sampled: flags == "01"
        }
      }
    else
      :invalid
    end
  end

  def decode(_), do: :invalid

  def encode(%__MODULE__{
        version: "00",
        trace_id: trace_id,
        parent_id: parent_id,
        flags: %{
          sampled: flags
        }
      }) do
    [
      "00",
      "-",
      String.pad_leading(trace_id, @trace_id, "0") |> String.downcase(),
      "-",
      String.pad_leading(parent_id, @parent_id, "0") |> String.downcase(),
      "-",
      (flags && "01") || "00"
    ]
    |> IO.iodata_to_binary()
  end
end
