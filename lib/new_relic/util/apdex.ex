defmodule NewRelic.Util.Apdex do
  @moduledoc false

  # https://en.wikipedia.org/wiki/Apdex

  def calculate(dur, apdex_t) when dur < apdex_t, do: :satisfying
  def calculate(dur, apdex_t) when dur < apdex_t * 4, do: :tolerating
  def calculate(_dur, _apdex_t), do: :frustrating

  def label(:satisfying), do: "S"
  def label(:tolerating), do: "T"
  def label(:frustrating), do: "F"
  def label(:ignore), do: nil
end
