defmodule NewRelic do
  @moduledoc """
  New Relic Agent - Public API
  """

  @doc """
  Set the name of the current transaction.

  The first segment will be treated as the Transaction namespace,
  and commonly contains the name of the framework.

  ## Notes
  * At least 2 segments are required to light up the Transactions UI in APM

  In the following example, you will see `/custom/transaction/name`
  in the Transaction list.

  ```elixir
  NewRelic.set_transaction_name("/Plug/custom/transaction/name")
  ```
  """
  @spec set_transaction_name(String.t()) :: any()
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

  ## Notes
  * Nested Lists and Maps are truncated at 10 items since there are a limited number
  of attributes that can be reported on Transaction events
  """
  @spec add_attributes(attributes :: Keyword.t()) :: any()
  defdelegate add_attributes(attributes), to: NewRelic.Transaction.Reporter

  @doc false
  @spec incr_attributes(attributes :: Keyword.t()) :: any()
  defdelegate incr_attributes(attributes), to: NewRelic.Transaction.Reporter

  @doc """
  Start an "Other" Transaction.

  This will begin monitoring the current process as an "Other" Transaction
  (ie: Not a "Web" Transaction).

  The first argument will be considered the "category", the second is the "name".

  The third argument is an optional map of headers that will connect this
  Transaction to an existing Distributed Trace. You can provide W3C "traceparent"
  and "tracestate" headers or another New Relic agent's "newrelic" header.

  The Transaction will end when the process exits, or when you call
  `NewRelic.stop_transaction()`

  ## Examples

  ```elixir
  NewRelic.start_transaction("GenStage", "MyConsumer/EventType")
  NewRelic.start_transaction("Task", "TaskName")
  NewRelic.start_transaction("WebSocket", "Handler", %{"newrelic" => "..."})
  ```

  > #### Warning {: .error}
  >
  > * You can't start a new transaction within an existing one. Any process
  > spawned inside a transaction belongs to that transaction.
  > * Do _not_ use this for processes that live a very long time, doing so
  > will risk increased memory growth tracking attributes in the transaction!

  ## Notes

  * Don't use this to track Web Transactions - Plug based HTTP servers
  are auto-instrumented based on `telemetry` events.
  * If multiple transactions are started in the same Process, you must
  call `NewRelic.stop_transaction/0` to mark the end of the Transaction.
  """
  @spec start_transaction(String.t(), String.t()) :: any()
  defdelegate start_transaction(category, name), to: NewRelic.OtherTransaction

  @spec start_transaction(String.t(), String.t(), headers :: map) :: any()
  defdelegate start_transaction(category, name, headers), to: NewRelic.OtherTransaction

  @doc """
  Stop an "Other" Transaction.

  If multiple Transactions are started in the same Process, you must
  call `NewRelic.stop_transaction/0` to mark the end of the Transaction.
  """
  @spec stop_transaction() :: any()
  defdelegate stop_transaction(), to: NewRelic.OtherTransaction

  @doc """
  Record an "Other" Transaction within the given block. The return value of
  the block is returned.

  See `start_transaction/2` and `stop_transaction/0` for more details about
  Transactions.

  ## Example

  ```elixir
  defmodule Worker do
    use NewRelic.Tracer

    def process_messages do
      NewRelic.other_transaction("Worker", "ProcessMessages") do
        # ...
      end
    end
  end
  ```
  """
  defmacro other_transaction(category, name, do: block) do
    quote do
      NewRelic.start_transaction(unquote(category), unquote(name))
      res = unquote(block)
      NewRelic.stop_transaction()
      res
    end
  end

  defmacro other_transaction(category, name, headers, do: block) do
    quote do
      NewRelic.start_transaction(unquote(category), unquote(name), unquote(headers))
      res = unquote(block)
      NewRelic.stop_transaction()
      res
    end
  end

  @doc """
  Call within a transaction to prevent it from reporting.

  ## Example

  ```elixir
  def index(conn, _) do
    NewRelic.ignore_transaction()
    send_resp(conn, 200, "Health check OK")
  end
  ```
  """
  @spec ignore_transaction() :: any()
  defdelegate ignore_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Call to exclude the current process from being part of the Transaction.

  ## Example:

  ```elixir
  Task.async(fn ->
    NewRelic.exclude_from_transaction()
    Work.wont_be_included()
  end)
  ```
  """
  @spec exclude_from_transaction() :: any()
  defdelegate exclude_from_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Advanced:
  Return a Transaction reference that can be used to manually connect a
  process to a Transaction with `NewRelic.connect_to_transaction/1`
  """
  @type tx_ref :: any()
  @spec get_transaction() :: tx_ref
  defdelegate get_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Advanced:
  Call to manually connect the current process to a Transaction. Pass in a reference
  returned by `NewRelic.get_transaction/0`

  Only use this when there is no auto-discoverable connection (ex: the process was
  spawned without links or the logic is within a message handling callback).

  This connection will persist until the process exits or
  `NewRelic.disconnect_from_transaction/0` is called.

  ## Example:

  ```elixir
  tx = NewRelic.get_transaction()

  spawn(fn ->
    NewRelic.connect_to_transaction(tx)
    # ...
  end)
  ```
  """
  @spec connect_to_transaction(tx_ref) :: any()
  defdelegate connect_to_transaction(ref), to: NewRelic.Transaction.Reporter

  @doc """
  Advanced:
  Call to manually disconnect the current process from the current Transaction.
  """
  @spec disconnect_from_transaction() :: any()
  defdelegate disconnect_from_transaction(), to: NewRelic.Transaction.Reporter

  @doc """
  Store information about the type of work the current span is doing.

  ## Examples

  ```elixir
  NewRelic.set_span(:generic, some: "attribute")

  NewRelic.set_span(:http, url: "https://elixir-lang.org", method: "GET", component: "HttpClient")

  NewRelic.set_span(:datastore, statement: statement, instance: instance, address: address,
  hostname: hostname, component: component)
  ```
  """
  @spec set_span(:generic, attributes :: Keyword.t()) :: any()
  @spec set_span(:http, url: String.t(), method: String.t(), component: String.t()) :: any()
  @spec set_span(:datastore,
          statement: String.t(),
          instance: String.t(),
          address: String.t(),
          hostname: String.t(),
          component: String.t()
        ) :: any()
  defdelegate set_span(type, attributes), to: NewRelic.DistributedTrace

  @doc """
  Add additional attributes to the current Span (not the current Transaction).

  Useful for reporting additional information about work being done in, for example,
  a function being traced with `@trace`

  ## Example

  ```elixir
  NewRelic.add_span_attributes(some: "attribute")
  ```
  """
  @spec add_span_attributes(attributes :: Keyword.t()) :: any()
  defdelegate add_span_attributes(attributes), to: NewRelic.DistributedTrace

  @doc """
  You must manually instrument outgoing HTTP calls to connect them to a Distributed Trace.

  The agent will automatically read HTTP request headers and detect if the request is a part
  of an incoming Distributed Trace, but outgoing requests need an extra header:

  ```elixir
  Req.get(url, headers: ["x-api-key": "secret"] ++ NewRelic.distributed_trace_headers(:http))
  ```

  ## Notes

  * Call `distributed_trace_headers` immediately before making the
  request since calling the function marks the "start" time of the request.
  """
  @spec distributed_trace_headers(:http) :: [{key :: String.t(), value :: String.t()}]
  @spec distributed_trace_headers(:other) :: map()
  defdelegate distributed_trace_headers(type), to: NewRelic.DistributedTrace

  @type name :: String.t() | {primary_name :: String.t(), secondary_name :: String.t()}

  @doc """
  Record a "Span" within the given block. The return value of the block is returned.

  ```elixir
  NewRelic.span("do.some_work", user_id: "abc123") do
    # do some work
  end
  ```

  Note: You can also use `@trace` annotations to instrument functions without modifying code.
  """
  @spec span(name :: name, attributes :: Keyword.t()) :: term()
  defmacro span(name, attributes \\ [], do: block) do
    quote do
      id = make_ref()
      NewRelic.Tracer.Direct.start_span(id, unquote(name), attributes: unquote(attributes))
      res = unquote(block)
      NewRelic.Tracer.Direct.stop_span(id)
      res
    end
  end

  @doc """
  See: `NewRelic.distributed_trace_headers/1`
  """
  @deprecated "Use distributed_trace_headers instead"
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
      NewRelic.sample_process()
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
  @spec sample_process() :: any()
  defdelegate sample_process, to: NewRelic.Sampler.Process

  @doc """
  Report a Custom event to NRDB.

  ## Example

  ```elixir
  NewRelic.report_custom_event("EventType", %{"foo" => "bar"})
  ```
  """
  @spec report_custom_event(type :: String.t(), event :: map()) :: any()
  defdelegate report_custom_event(type, event),
    to: NewRelic.Harvest.Collector.CustomEvent.Harvester

  @doc """
  Report a Dimensional Metric.

  Valid types: `:count`, `:gauge`, and `:summary`.

  ## Example

  ```elixir
  NewRelic.report_dimensional_metric(:count, "my_metric_name", 1, %{some: "attributes"})
  ```
  """
  @spec report_dimensional_metric(
          type :: :count | :gauge | :summary,
          name :: String.t(),
          value :: number,
          attributes :: map()
        ) :: any()
  defdelegate report_dimensional_metric(type, name, value, attributes \\ %{}),
    to: NewRelic.Harvest.TelemetrySdk.DimensionalMetrics.Harvester

  @doc """
  Report a Custom metric.

  ## Example

  ```elixir
  NewRelic.report_custom_metric("My/Metric", 123)
  ```
  """
  @spec report_custom_metric(name :: String.t(), value :: number()) :: any()
  defdelegate report_custom_metric(name, value),
    to: NewRelic.Harvest.Collector.Metric.Harvester

  @doc """
  Increment a Custom metric.

  ## Example

  ```elixir
  NewRelic.increment_custom_metric("My/Metric")
  ```
  """
  @spec increment_custom_metric(name :: String.t(), count :: integer()) :: any()
  defdelegate increment_custom_metric(name, count \\ 1),
    to: NewRelic.Harvest.Collector.Metric.Harvester

  @doc """
  Report an Exception inside a Transaction.

  This should only be used when you `rescue` an exception inside a Transaction,
  but still want to report it. All un-rescued exceptions are already reported as errors.

  ## Example

  ```elixir
  try do
    raise RuntimeError
  rescue
    exception -> NewRelic.notice_error(exception, __STACKTRACE__)
  end
  ```
  """
  @spec notice_error(Exception.t(), Exception.stacktrace()) :: any()
  defdelegate notice_error(exception, stacktrace), to: NewRelic.Transaction.Reporter

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
