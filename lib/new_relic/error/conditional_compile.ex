defmodule NewRelic.ConditionalCompile do
  @moduledoc false

  defmacro before_elixir_version(version, code) do
    if Version.compare(System.version(), version) == :lt do
      quote do
        unquote(code)
      end
    end
  end
end
