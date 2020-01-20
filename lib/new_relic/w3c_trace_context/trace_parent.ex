defmodule NewRelic.W3CTraceContext.TraceParent do
  defstruct version: "00",
            trace_id: nil,
            parent_id: nil,
            flags: nil

  use Bitwise

  @trace_id 32
  @parent_id 16
  @flags 2

  def decode(<<"00", "-", "00000000000000000000000000000000", _::binary>>),
    do: :invalid

  def decode(<<"00", "-", _::binary-size(@trace_id), "-", "0000000000000000", _::binary>>),
    do: :invalid

  def decode(
        <<"00", "-", trace_id::binary-size(@trace_id), "-", parent_id::binary-size(@parent_id),
          "-", flags::binary-size(@flags)>>
      ) do
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
