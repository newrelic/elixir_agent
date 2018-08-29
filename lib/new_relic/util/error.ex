defmodule NewRelic.Util.Error do
  # Helper functions for normalizing and formatting errors

  @moduledoc false

  def normalize(exception, stacktrace, initial_call \\ nil) do
    normalized_error = Exception.normalize(:error, exception, stacktrace)

    exception_type = normalized_error.__struct__
    exception_reason = format_reason(normalized_error)
    exception_stacktrace = format_stacktrace(stacktrace, initial_call)

    {exception_type, exception_reason, exception_stacktrace}
  end

  def format_reason(error),
    do:
      :error
      |> Exception.format_banner(error)
      |> String.replace("** ", "")

  def format_stacktrace(stacktrace, initial_call),
    do:
      stacktrace
      |> prepend_initial_call(initial_call)
      |> Enum.map(&Exception.format_stacktrace_entry/1)

  defp prepend_initial_call(stacktrace, {mod, fun, args}),
    do: stacktrace ++ [{mod, fun, args, []}]

  defp prepend_initial_call(stacktrace, _), do: stacktrace
end
