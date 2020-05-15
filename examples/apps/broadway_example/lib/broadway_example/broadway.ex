defmodule BroadwayExample.Broadway do
  use Broadway

  require Logger

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {Broadway.DummyProducer, []}],
      processors: [example_processor_key: [concurrency: 2]],
      batchers: [example_batcher_key: [concurrency: 1]]
    )
  end

  def handle_message(:example_processor_key, message, _context) do
    Logger.debug("Message arrived #{message.data}")

    message
    |> Broadway.Message.put_batcher(:example_batcher_key)
  end

  def handle_batch(:example_batcher_key, messages, _batch_info, _context) do
    Logger.debug("Batch arrived #{inspect(Enum.map(messages, & &1.data))}")
    messages
  end
end
