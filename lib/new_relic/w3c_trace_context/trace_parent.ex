defmodule NewRelic.W3CTraceContext.TraceParent do
  defstruct version: "00", trace_id: nil, parent_id: nil, flags: nil

  use Bitwise
  @hex 16

  def decode(<<"00", "-", "00000000000000000000000000000000", _::binary>>), do: :invalid
  def decode(<<"00", "-", _::binary-32, "-", "0000000000000000", _::binary>>), do: :invalid

  def decode(<<"00", "-", trace_id::binary-32, "-", parent_id::binary-16, "-", flags::binary-2>>) do
    %__MODULE__{
      version: "00",
      trace_id: String.to_integer(trace_id, @hex),
      parent_id: String.to_integer(parent_id, @hex),
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
      :io_lib.format("~32.16.0b", [tp.trace_id]),
      "-",
      :io_lib.format("~16.16.0b", [tp.parent_id]),
      "-",
      flags
    ]
    |> IO.iodata_to_binary()
  end
end
