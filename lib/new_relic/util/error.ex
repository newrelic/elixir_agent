defmodule NewRelic.Util.Error do
  # Helper functions for normalizing and formatting errors

  @moduledoc false

  def normalize(kind, exception, stacktrace, initial_call \\ nil)

  def normalize(kind, exception, stacktrace, initial_call) do
    normalized_error = Exception.normalize(kind, exception, stacktrace)

    exception_type = format_type(kind, normalized_error)
    exception_reason = format_reason(kind, normalized_error)
    exception_stacktrace = format_stacktrace(stacktrace, initial_call)

    {exception_type, exception_reason, exception_stacktrace}
  end

  defp format_type(:error, %ErlangError{original: {_reason, {module, function, args}}}),
    do: Exception.format_mfa(module, function, length(args))

  defp format_type(_, %{__exception__: true, __struct__: struct}), do: inspect(struct)
  defp format_type(:exit, _reason), do: "EXIT"

  def format_reason(:error, %ErlangError{original: {reason, {module, function, args}}}),
    do: "(" <> Exception.format_mfa(module, function, length(args)) <> ") " <> inspect(reason)

  def format_reason(:error, error),
    do:
      :error
      |> Exception.format_banner(error)
      |> String.replace("** ", "")

  def format_reason(:exit, {reason, {module, function, args}}),
    do: "(" <> Exception.format_mfa(module, function, length(args)) <> ") " <> inspect(reason)

  def format_reason(:exit, %{__exception__: true} = error), do: format_reason(:error, error)
  def format_reason(:exit, reason), do: inspect(reason)

  def format_stacktrace(stacktrace, initial_call),
    do:
      maybe_remove_args_from_stacktrace(stacktrace)
      |> List.wrap()
      |> prepend_initial_call(initial_call)
      |> Enum.map(fn
        line when is_binary(line) -> line
        entry when is_tuple(entry) -> Exception.format_stacktrace_entry(entry)
      end)

  defp prepend_initial_call(stacktrace, {mod, fun, args}) do
    if NewRelic.Config.feature?(:stacktrace_argument_collection) do
      stacktrace ++ [{mod, fun, args, []}]
    else
      stacktrace ++ [{mod, fun, ["DISABLED (arity: #{length(args)})"], []}]
    end
  end

  defp prepend_initial_call(stacktrace, _) do
    stacktrace
  end

  defp maybe_remove_args_from_stacktrace(stacktrace) do
    if NewRelic.Config.feature?(:stacktrace_argument_collection) do
      stacktrace
    else
      remove_args_from_stacktrace(stacktrace)
    end
  end

  defp remove_args_from_stacktrace([{mod, fun, [_ | _] = args, info} | rest]),
    do: [{mod, fun, ["DISABLED (arity: #{length(args)})"], info} | rest]

  defp remove_args_from_stacktrace(stacktrace) when is_list(stacktrace),
    do: stacktrace
end
