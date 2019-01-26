defmodule NewRelic.Util.Apdex do
  @moduledoc false

  # https://en.wikipedia.org/wiki/Apdex

  def calculate(dur, apdex_t) when dur < apdex_t,
    do: {:satisfying, apdex_t}

  def calculate(dur, apdex_t) when dur < apdex_t * 4,
    do: {:tolerating, apdex_t}

  def calculate(dur, apdex_t),
    do: {:frustrating, apdex_t}
end
