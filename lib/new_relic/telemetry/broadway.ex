defmodule NewRelic.Telemetry.Broadway do
  @moduledoc """
  `Broadway` pipelines are auto-instrumented based on the `telemetry`.

  When you create some `Broadway`-based pipeline, it translates into a topology
  of `GenStage` processes. The agent wraps each `GenStage` work unit of work into
  their own Transactions. Example, the following topology:

  ```elixir
  defmodule MyBroadway do
    use Broadway

    def start_link(_opts) do
      Broadway.start_link(MyBroadway,
        name: MyBroadwayExample,
        producer: [
          module: {Counter, []},
          concurrency: 1
        ],
        processors: [
          default: [concurrency: 2]
        ],
        batchers: [
          sqs: [concurrency: 2, batch_size: 10],
          s3: [concurrency: 1, batch_size: 10]
        ]
      )
    end

    ...callbacks...
  end
  ```

  You can expected the following Transactions:
  - Broadway/MyBroadway/Processor/default: one Transaction per message processed by `:default`.
  - Broadway/MyBroadway/Consumer/sqs: one Transaction per batch of messages forwarded to `:sqs`.
  - Broadway/MyBroadway/Consumer/s3: one Transaction per batch os messages forwarded to `:s3`.

  The nomenclature adopted here, Consumer instead of Batcher, maps the underlying `Broadway`
  topology, as you can read on their [architecture guides](https://hexdocs.pm/broadway/architecture.html).

  To prevent reporting the current transaction, call:

  ```elixir
  NewRelic.ignore_transaction()
  ```

  Inside a Transaction, the agent will track work across processes that are spawned as
  well as work done inside a Task Supervisor. When using `Task.Supervisor.async_nolink`
  you can signal to the agent not to track the work done inside the Task, which will
  exclude it from the current Transaction. To do this, send in an additional option:

  ```elixir
  Task.Supervisor.async_nolink(
    MyTaskSupervisor,
    fn -> do_work() end,
    new_relic: :no_track
  )
  ```
  """
  use GenServer

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @message_start [:broadway, :processor, :message, :start]
  @message_stop [:broadway, :processor, :message, :stop]
  @message_failure [:broadway, :processor, :message, :failure]

  @consumer_start [:broadway, :consumer, :start]
  @consumer_stop [:broadway, :consumer, :stop]

  @broadway_events [
    @message_start,
    @message_stop,
    @message_failure,
    @consumer_start,
    @consumer_stop
  ]

  @doc false
  def init(:ok) do
    config = %{
      handler_id: {:new_relic, :broadway}
    }

    :telemetry.attach_many(
      config.handler_id,
      @broadway_events,
      &__MODULE__.handle_event/4,
      config
    )

    Process.flag(:trap_exit, true)
    {:ok, config}
  end

  @doc false
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(_event, _measurements, _metadata, _config)

  def handle_event(
        @message_start,
        %{time: system_time},
        %{name: name, processor_key: processor_key},
        _config
      ) do
    module_name = extract_callback_module_name(name)
    NewRelic.start_transaction("Broadway", processor_name(module_name, processor_key))
    NewRelic.add_attributes(processor_start_attrs(module_name, processor_key, system_time))
  end

  def handle_event(
        @message_stop,
        %{duration: duration},
        _metadata,
        _config
      ) do
    NewRelic.add_attributes(processor_stop_attrs(duration))
    NewRelic.stop_transaction()
  end

  def handle_event(
        @message_failure,
        %{duration: duration},
        %{kind: kind, reason: reason, stacktrace: stack},
        _config
      ) do
    NewRelic.Transaction.Reporter.fail(%{kind: kind, reason: reason, stack: stack})
    NewRelic.add_attributes(processor_stop_attrs(duration))
    NewRelic.stop_transaction()
  end

  def handle_event(
        @consumer_start,
        %{time: system_time},
        %{name: name, batch_info: batch_info},
        _config
      ) do
    module_name = extract_callback_module_name(name)
    NewRelic.start_transaction("Broadway", consumer_name(module_name, batch_info.batcher))
    NewRelic.add_attributes(consumer_start_attrs(module_name, batch_info, system_time))
  end

  def handle_event(
        @consumer_stop,
        %{duration: duration},
        %{successful_messages: successful_messages, failed_messages: failed_messages},
        _config
      ) do
    NewRelic.add_attributes(consumer_stop_attrs(duration, successful_messages, failed_messages))
    NewRelic.stop_transaction()
  end

  def handle_event(_event, _measurements, _meta, _config) do
    :ignore
  end

  defp extract_callback_module_name(name),
    do: name |> Module.split() |> Enum.drop(-2) |> Enum.join(".")

  defp processor_name(module_name, processor_key),
    do: "#{module_name}/Processor/#{processor_key}"

  defp processor_start_attrs(module_name, processor_key, system_time) do
    [
      system_time: system_time,
      "broadway.module": module_name,
      "broadway.stage": :processor,
      "broadway.processor_key": processor_key
    ]
  end

  defp processor_stop_attrs(duration) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      memory_kb: _bytes_to_kilobytes = info[:memory] / 1024,
      reductions: info[:reductions]
    ]
  end

  defp consumer_name(module_name, batcher),
    do: "#{module_name}/Consumer/#{batcher}"

  defp consumer_start_attrs(module_name, batch_info, system_time) do
    [
      system_time: system_time,
      "broadway.module": module_name,
      "broadway.stage": :consumer,
      "broadway.batcher": batch_info.batcher,
      "broadway.batch_info.batch_key": batch_info.batch_key,
      "broadway.batch_info.partition": batch_info.partition,
      "broadway.batch_info.size": batch_info.size
    ]
  end

  defp consumer_stop_attrs(duration, successful_messages, failed_messages) do
    info = Process.info(self(), [:memory, :reductions])

    [
      duration: duration,
      memory_kb: _bytes_to_kilobytes = info[:memory] / 1024,
      reductions: info[:reductions],
      "broadway.successful_messages_count": length(successful_messages),
      "broadway.failed_messages_count": length(failed_messages)
    ]
  end
end
