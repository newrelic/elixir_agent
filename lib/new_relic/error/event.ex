defmodule NewRelic.Error.Event do
  defstruct type: "TransactionError",
            timestamp: nil,
            error_class: nil,
            error_message: nil,
            expected: false,
            transaction_name: nil,
            duration: nil,
            database_duration: nil,
            user_attributes: %{},
            agent_attributes: %{}

  @moduledoc false

  def format_events(errors) do
    Enum.map(errors, &format_event/1)
  end

  defp format_event(%__MODULE__{} = error) do
    [
      _intrinsic_attributes = %{
        type: error.type,
        timestamp: error.timestamp,
        "error.class": error.error_class,
        "error.message": error.error_message,
        "error.expected": error.expected,
        transactionName: error.transaction_name,
        duration: error.duration,
        databaseDuration: error.database_duration
      },
      NewRelic.Util.Event.process_event(error.user_attributes),
      format_agent_attributes(error.agent_attributes)
    ]
  end

  defp format_agent_attributes(%{
         http_response_code: http_response_code,
         request_method: request_method
       }) do
    %{
      httpResponseCode: http_response_code,
      "request.headers.method": request_method
    }
  end

  defp format_agent_attributes(_agent_attributes) do
    %{}
  end
end
