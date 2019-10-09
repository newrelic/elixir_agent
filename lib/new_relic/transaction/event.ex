defmodule NewRelic.Transaction.Event do
  defstruct type: "Transaction",
            web_duration: nil,
            database_duration: nil,
            timestamp: nil,
            name: nil,
            duration: nil,
            total_time: nil,
            user_attributes: %{},
            queue_duration: nil

  @moduledoc false

  def format_events(transactions) do
    Enum.map(transactions, &format_event/1)
  end

  def format_event(%__MODULE__{} = transaction) do
    [
      %{
        webDuration: transaction.web_duration,
        totalTime: transaction.total_time,
        databaseDuration: transaction.database_duration,
        timestamp: transaction.timestamp,
        name: transaction.name,
        duration: transaction.duration,
        type: transaction.type,
        queueDuration: transaction.queue_duration
      },
      NewRelic.Util.Event.process_event(transaction.user_attributes)
    ]
  end
end
