defmodule NewRelic.Util.Event do
  @moduledoc false

  def process_event(event), do: Map.new(event, &process_attr/1)

  defp process_attr({key, val}) when is_binary(val), do: {key, val |> limit_size}
  defp process_attr({key, val}) when is_bitstring(val), do: {key, val |> inspect |> limit_size}
  defp process_attr({key, val}) when is_pid(val), do: {key, val |> inspect}
  defp process_attr({key, val}), do: {key, val}

  @max_string 4096
  defp limit_size(string) when byte_size(string) < @max_string, do: string

  defp limit_size(string) do
    index = find_truncation_point(string)
    String.slice(string, 0, index)
  end

  defp find_truncation_point(string, len \\ 0)

  defp find_truncation_point("", len), do: len

  defp find_truncation_point(string, len) do
    case next_grapheme_size(string) do
      {char_size, rest} when len + char_size < @max_string ->
        find_truncation_point(rest, len + char_size)

      _ ->
        len
    end
  end

  defp next_grapheme_size(string) do
    {grapheme, rest} = String.next_grapheme(string)
    {byte_size(grapheme), rest}
  end
end
