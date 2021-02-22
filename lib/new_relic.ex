defmodule NewRelic do
  @moduledoc """
  New Relic Agent - Public API
  """

  @doc """
  Set the name of the current transaction.

  The first segment will be treated as the Transaction namespace,
  and commonly contains the name of the framework.

  **Notes:**
  * At least 2 segments are required to light up the Transactions UI in APM

  In the following example, you will see `/custom/transaction/name`
  in the Transaction list.

  ```elixir
  NewRelic.set_transaction_name("/Plug/custom/transaction/name")
  ```
  """
  defdelegate set_transaction_name(name), to: NewRelic.Transaction.Reporter

  @doc """
  Report custom attributes on the current Transaction

  Reporting nested data structures is supported by auto-flattening them
  into a list of key-value pairs.

  ```elixir
  NewRelic.add_attributes(foo: "bar")
    # "foo" => "bar"

  NewRelic.add_attributes(map: %{foo: "bar", baz: "qux"})
    # "map.foo" => "bar"
    # "map.baz" => "qux"
    # "map.size" => 2

  NewRelic.add_attributes(list: ["a", "b", "c"])
    # "list.0" => "a"
    # "list.1" => "b"
    # "list.2" => "c"
    # "list.length" => 3
  ```

  **Notes:**
  * Nested Lists and Maps are truncated at 10 items since there are a limited number
  of attributes that can be reported on Transaction events
  """
  defdelegate add_attributes(custom_attributes), to: NewRelic.Transaction.Reporter

  @doc false
  defdelegate incr_attributes(attrs), to: NewRelic.Transaction.Reporter

  @doc """
  Start an "Other" Transaction.

  This will begin monitoring the current process as an "Other" Transaction
  (ie: Not a "Web" Transaction). The first argument will be considered
  the "category", the second is the "name".

  Examples:

  ```elixir
  NewRelic.start_transaction("GenStage", "MyConsumer/EventType")
  NewRelic.start_transaction("Task", "TaskName")
  ```

  **Notes:**

  * Don't use this to track Web Transactions - Plug based HTTP servers
  are auto-instrumented based on `telemetry` events.
  * Do _not_ use this for processes that live a very long time, doing so
  will risk a memory leak tracking attributes in the transaction!
  * You can't start a new transaction within an existing one. Any process
  spawned inside a transaction belongs to that transaction.
  * If multiple transactions are started in the same Process, you must
  call `NewRelic.stop_transaction()` to mark the end of the transaction.
  """
  @spec start_transaction(String.t(), String.t()) :: :ok
  defdelegate start_transaction(category, name), to: NewRelic.OtherTransaction

  @doc """
  Stop an "Other" Transaction.

  If multiple transactions are started in the same Process, you must
  call `NewRelic.stop_transaction()` to mark the end of the transaction.
  """
  @spec stop_transaction() :: :ok
  defdelegate stop_transaction(), to: NewRelic.OtherTransaction

  @doc """
  Define an "Other" transaction within the given block. The return value of
  the block is returned.

  See `start_transaction` and `stop_transaction` for more details.
  """
  defmacro other_transaction(category, name, do: block) do
    quote do
      NewRelic.start_transaction(unquote(category), unquote(name))
      res = unquote(block)
      NewRelic.stop_transaction()
      res
    end
  end

  @doc """
  Call within a transaction to prevent it from reporting.

  ```elixir
  def index(conn, _) do
    NewRelic.ignore_transaction()
    send_resp(conn, 200, "Health check OK")
  end
  ```
  """
  defdelegate ignore_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Call to exclude the current process from being part of the Transaction.
  """
  defdelegate exclude_from_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Advanced:
  Call to manually connect the current process to another process's Transaction.

  Only use this when there is no auto-discoverable connection (ex: the process was
  spawned without links or the logic is within a message handling callback).

  This connection will persist until the process exits or
  `NewRelic.disconnect_from_transaction()` is called.
  """
  defdelegate connect_to_transaction(pid), to: NewRelic.Transaction.Reporter

  @doc """
  Advanced:
  Call to manually connect a `Task` process to the process which called it.

  Only needed when a `Task` is spawned without a link to the calling process,
  eg: `Task.Supervisor.async_nolink`.

  This connection will persist until the process exits or
  `NewRelic.disconnect_from_transaction()` is called.
  """
  defdelegate connect_task_to_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Advanced:
  Call to manually disconnect the current proccess from the current Transaction.
  """
  defdelegate disconnect_from_transaction(), to: NewRelic.Transaction.Reporter

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
  of an incoming Distributed Trace, but outgoing requests need an extra header:

  ```elixir
  HTTPoison.get(url, ["x-api-key": "secret"] ++ NewRelic.distributed_trace_headers(:http))
  ```

  **Notes:**

  * Call `NewRelic.distributed_trace_headers` immediately before making the
  request since calling the function marks the "start" time of the request.
  """
  defdelegate distributed_trace_headers(type), to: NewRelic.DistributedTrace

  @deprecated "Use distributed_trace_headers/1 instead"
  defdelegate create_distributed_trace_payload(type),
    to: NewRelic.DistributedTrace,
    as: :distributed_trace_headers

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

  @doc """
  Report a Custom metric.

  ```elixir
  NewRelic.report_custom_metric("My/Metric", 123)
  ```
  """
  defdelegate report_custom_metric(name, value),
    to: NewRelic.Harvest.Collector.Metric.Harvester

  @doc false
  defdelegate enable_erlang_trace, to: NewRelic.Transaction.ErlangTraceManager

  @doc false
  defdelegate disable_erlang_trace, to: NewRelic.Transaction.ErlangTraceManager

  @doc false
  defdelegate report_aggregate(meta, values), to: NewRelic.Aggregate.Reporter

  @doc false
  defdelegate report_sample(category, values), to: NewRelic.Sampler.Reporter

  @doc false
  defdelegate report_span(span), to: NewRelic.Span.Reporter

  @doc false
  defdelegate report_metric(identifier, values), to: NewRelic.Harvest.Collector.Metric.Harvester

  @doc false
  defdelegate log(level, message), to: NewRelic.Logger

  @doc false
  defdelegate manual_shutdown(), to: NewRelic.Harvest.Supervisor
end
