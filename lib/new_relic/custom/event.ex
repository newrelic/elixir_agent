defmodule NewRelic.Custom.Event do
  defstruct type: nil,
            timestamp: nil,
            attributes: %{}

  @moduledoc false

  # Struct for reporting Custom events

  def format_events(events) do
    Enum.map(events, &format_event/1)
  end

  defp format_event(%__MODULE__{} = event) do
    [
      %{
        type: event.type,
        timestamp: event.timestamp
      },
      NewRelic.Util.Event.process_event(event.attributes),
      %{}
    ]
  end
end
