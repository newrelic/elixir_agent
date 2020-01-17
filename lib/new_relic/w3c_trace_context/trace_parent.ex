defmodule NewRelic.W3CTraceContext.TraceParent do
  defstruct version: "00",
            trace_id: nil,
            parent_id: nil,
            flags: nil

  use Bitwise

  def decode(<<"00", "-", "00000000000000000000000000000000", _::binary>>), do: :invalid
  def decode(<<"00", "-", _::binary-32, "-", "0000000000000000", _::binary>>), do: :invalid

  def decode(<<"00", "-", trace_id::binary-32, "-", parent_id::binary-16, "-", flags::binary-2>>) do
    %__MODULE__{
      version: "00",
      trace_id: trace_id,
      parent_id: parent_id,
      flags: %{
        sampled: flags == "01"
      }
    }
  end

  def decode(_), do: :invalid

  def encode(%__MODULE__{version: "00"} = tp) do
    flags = (tp.flags.sampled && "01") || "00"

    [
      "00",
      "-",
      String.pad_leading(tp.trace_id, 32, "0") |> String.downcase(),
      "-",
      String.pad_leading(tp.parent_id, 16, "0") |> String.downcase(),
      "-",
      flags
    ]
    |> IO.iodata_to_binary()
  end
end
