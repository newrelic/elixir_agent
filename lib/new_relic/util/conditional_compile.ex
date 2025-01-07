defmodule NewRelic.Util.ConditionalCompile do
  @moduledoc false
  def match?(version) do
    Version.match?(System.version(), version)
  end
end
