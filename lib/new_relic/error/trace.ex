defmodule NewRelic.Error.Trace do
  defstruct timestamp: nil,
            transaction_name: "",
            message: nil,
            expected: false,
            error_type: nil,
            cat_guid: "",
            stack_trace: nil,
            request_uri: nil,
            user_attributes: %{}

  @moduledoc false

  def format_errors(errors) do
    Enum.map(errors, &format_error/1)
  end

  def format_error(%__MODULE__{} = error) do
    [
      error.timestamp,
      error.transaction_name,
      error.message,
      error.error_type,
      %{
        stack_trace: error.stack_trace,
        request_uri: error.request_uri,
        agentAttributes: %{},
        userAttributes: format_user_attributes(error.user_attributes),
        intrinsics: %{"error.expected": error.expected}
      },
      error.cat_guid
    ]
  end

  defp format_user_attributes(attrs) do
    Enum.into(attrs, %{}, fn {k, v} ->
      (String.Chars.impl_for(v) && {k, v}) || {k, inspect(v)}
    end)
  end
end
