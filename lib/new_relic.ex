defmodule NewRelic do
  @moduledoc """
  New Relic Agent - Public API
  """

  @doc """
  Set the name of the current transaction.

  The first segment will be treated as the Transaction namespace,
  and commonly contains the name of the framework.

  In the following example, you will see `/custom/transaction/name`
  in the Transaction list.

  ```elixir
  NewRelic.set_transaction_name("/Plug/custom/transaction/name")
  ```
  """
  defdelegate set_transaction_name(name), to: NewRelic.Transaction.Reporter

  @doc """
  Report a custom attribute on the current transaction

  ```elixir
  NewRelic.add_attributes(foo: "bar")
  ```
  """
  defdelegate add_attributes(custom_attributes), to: NewRelic.Transaction.Reporter

  @doc false
  defdelegate incr_attributes(attrs), to: NewRelic.Transaction.Reporter

  @doc """
  Start a new "Other" Transaction.

  This will begin monitoring the current process as an "Other" Transaction
  (ie: Not a "Web" Transaction). The first argument will be considered
  the "category", the second is the "name".

  Examples:

  ```elixir
  NewRelic.start_transaction("GenStage", "MyConsumer/EventType")
  NewRelic.start_transaction("Task", "TaskName")
  ```

  **Notes:**

  * Don't use this to track Web Transactions - for that,
  `use NewRelic.Transaction` in your Plug pipeline so that we can properly
  categorize as Web Transactions in the UI.
  * Do _not_ use this for processes that live a very long time, doing so
  will risk a memory leak tracking attributes in the transaction!
  * You can't start a new transaction within an existing one. Any process
  spawned inside a transaction belongs to that transaction.
  """
  @spec start_transaction(String.t(), String.t()) :: none()
  defdelegate start_transaction(category, name), to: NewRelic.Transaction

  @doc """
  Call within a transaction to prevent it from reporting.

  ```elixir
  def index(conn, %{}) do
    NewRelic.ignore_transaction()
    send_resp(conn, :ok, '')
  end
  ```
  """
  defdelegate ignore_transaction(), to: NewRelic.Transaction

  @doc """
  Store information about the type of work the current span is doing.

  Options:
  - `:generic, custom: attributes`
  - `:http, url: url, method: method, component: component`
  - `:datastore, statement: statement, instance: instance, address: address, hostname: hostname, component: component`
  """
  defdelegate set_span(type, attributes), to: NewRelic.DistributedTrace

  @doc """
  You must manually instrument outgoing HTTP calls to connect them to a Distributed Trace.

  The agent will automatically read request headers and detect if the request is a part
  of a Distributed Trace, but outgoing requests need an extra header:

  ```elixir
  dt_header_payload = NewRelic.create_distributed_trace_payload(:http)
  HTTPoison.get(url, ["x-api-key": "secret"] ++ dt_header_payload)
  ```

  **Notes:**

  * Call `NewRelic.create_distributed_trace_payload` immediately before making the
  request since calling the function marks the "start" time of the request.
  """
  defdelegate create_distributed_trace_payload(type), to: NewRelic.DistributedTrace

  @doc """
  To get detailed information about a particular process, you can install a Process sampler.
  You must tell the Agent about your process from within the process.

  For a `GenServer`, this function call should be made in the `init` function:

  ```elixir
  defmodule ImportantProcess do
    use GenServer
    def init(:ok) do
      NewRelic.sample_process
      {:ok, %{}}
    end
  end
  ```

  Once installed, the agent will report `ElixirSample` events with:

  * `category = "Process"`
  * `message_queue_length`
  * `reductions`
  * `memory_kb`
  """
  defdelegate sample_process, to: NewRelic.Sampler.Process

  @doc """
  Report a Custom event to NRDB.

  ```elixir
  NewRelic.report_custom_event("EventType", %{"foo" => "bar"})
  ```
  """
  defdelegate report_custom_event(type, attributes),
    to: NewRelic.Harvest.Collector.CustomEvent.Harvester

  @doc false
  defdelegate report_aggregate(meta, values), to: NewRelic.Aggregate.Reporter

  @doc false
  defdelegate report_sample(category, values), to: NewRelic.Sampler.Reporter

  @doc false
  defdelegate report_span(span), to: NewRelic.Harvest.Collector.SpanEvent.Harvester

  @doc false
  defdelegate report_metric(identifier, values), to: NewRelic.Harvest.Collector.Metric.Harvester

  @doc false
  defdelegate log(level, message), to: NewRelic.Logger

  @doc false
  defdelegate manual_shutdown(), to: NewRelic.Harvest.Supervisor
end
