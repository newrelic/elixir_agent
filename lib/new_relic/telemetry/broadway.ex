defmodule NewRelic.Telemetry.Broadway do
  @moduledoc false
  use GenServer

  alias NewRelic.Transaction
  alias NewRelic.DistributedTrace

  require Logger

  @processor_start [:broadway, :processor, :start]
  @processor_stop [:broadway, :processor, :stop]

  @message_stop [:broadway, :processor, :message, :stop]
  @message_fail [:broadway, :processor, :message, :failure]

  @consumer_start [:broadway, :consumer, :start]
  @consumer_stop [:broadway, :consumer, :stop]

  def start_link() do
    enabled = true
    GenServer.start_link(__MODULE__, [enabled: enabled], name: __MODULE__)
  end

  def init(enabled: false), do: :ignore

  def init(enabled: true) do
    config = %{
      handler_id: :new_relic_broadway
    }

    :telemetry.attach_many(
      config.handler_id,
      [
        @processor_start,
        @processor_stop,
        @message_stop,
        @message_fail,
        @consumer_start,
        @consumer_stop
      ],
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  def handle_event(@processor_start, _measurements, metadata, _config) do
    NewRelic.start_transaction("Broadway", processor_name(metadata))
    NewRelic.add_attributes(processor_start_attributes(metadata))
  end

  def handle_event(@processor_stop, _measurements, metadata, _config) do
    NewRelic.add_attributes(processor_stop_attributes(metadata))
    NewRelic.stop_transaction()
  end

  def handle_event(@message_stop, measurements, metadata, _config) do
    track_message_segment(measurements, metadata)
  end

  def handle_event(@message_fail, measurements, metadata, _config) do
    track_message_segment(measurements, metadata, %{
      kind: metadata.kind,
      reason: metadata.reason,
      stack: metadata.stacktrace
    })
  end

  def handle_event(@consumer_start, _measurements, metadata, _config) do
    NewRelic.start_transaction("Broadway", consumer_name(metadata))
    NewRelic.add_attributes(consumer_start_attributes(metadata))
  end

  def handle_event(@consumer_stop, _measurements, metadata, _config) do
    NewRelic.add_attributes(consumer_stop_attributes(metadata))
    NewRelic.stop_transaction()
  end

  defp extract_callback_module_name(name) do
    Module.split(name) |> :lists.reverse() |> Enum.drop(2) |> :lists.reverse() |> Enum.join(".")
  end

  defp processor_name(%{name: name}) do
    %{"processor_key" => processor_key} =
      Regex.named_captures(~r/Processor_(?<processor_key>\w+)_\d+$/, to_string(name))

    "#{extract_callback_module_name(name)}/Processor/#{processor_key}"
  end

  defp processor_start_attributes(%{name: name, messages: messages}) do
    [
      "broadway.module": extract_callback_module_name(name),
      "broadway.stage": :processor,
      "broadway.processor.message_count": length(messages)
    ]
  end

  defp processor_stop_attributes(metadata) do
    info = Process.info(self(), [:memory, :reductions])

    [
      "broadway.processor.successful_to_ack_count": length(metadata.successful_messages_to_ack),
      "broadway.processor.successful_to_forward_count":
        length(metadata.successful_messages_to_forward),
      "broadway.processor.failed_count": length(metadata.failed_messages),
      memory_kb: _bytes_to_kilobytes = info[:memory] / 1024,
      reductions: info[:reductions]
    ]
  end

  def track_message_segment(
        %{duration: duration},
        %{name: name, processor_key: processor_key},
        error \\ nil
      ) do
    end_time_ms = System.system_time(:millisecond)
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    duration_s = duration_ms / 1000
    start_time_ms = end_time_ms - duration_ms

    pid = inspect(self())
    id = {:broadway_message, make_ref()}
    parent_id = Process.get(:nr_current_span) || :root

    metric_name = "#{extract_callback_module_name(name)}/Processor/#{processor_key}/Message"

    if error, do: Transaction.Reporter.fail(error)

    Transaction.Reporter.add_trace_segment(%{
      primary_name: metric_name,
      secondary_name: metric_name,
      attributes: %{
        "broadway.processor_key": processor_key
      },
      error: !!error,
      pid: pid,
      id: id,
      parent_id: parent_id,
      start_time: start_time_ms,
      end_time: end_time_ms
    })

    NewRelic.report_span(
      timestamp_ms: start_time_ms,
      duration_s: duration_s,
      name: metric_name,
      edge: [span: id, parent: parent_id],
      category: "generic",
      attributes: %{
        component: "Broadway",
        "broadway.processor_key": processor_key
      }
    )
  end

  defp consumer_name(%{name: name, batch_info: batch_info}) do
    "#{extract_callback_module_name(name)}/Consumer/#{batch_info.batcher}"
  end

  defp consumer_start_attributes(metadata) do
    [
      "broadway.module": extract_callback_module_name(metadata.name),
      "broadway.stage": :consumer,
      "broadway.batcher": metadata.batch_info.batcher,
      "broadway.batch_key": metadata.batch_info.batch_key,
      "broadway.batch_partition": metadata.batch_info.partition,
      "broadway.batch_size": metadata.batch_info.size
    ]
  end

  defp consumer_stop_attributes(metadata) do
    info = Process.info(self(), [:memory, :reductions])

    [
      "broadway.batch_successful_count": length(metadata.successful_messages),
      "broadway.batch_failed_count": length(metadata.failed_messages),
      memory_kb: _bytes_to_kilobytes = info[:memory] / 1024,
      reductions: info[:reductions]
    ]
  end
end
