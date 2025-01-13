defmodule NewRelic.Tracer do
  @moduledoc """
  Function Tracing

  To enable function tracing in a particular module, `use NewRelic.Tracer`,
  and annotate the functions you want to trace with `@trace`.

  Traced functions will report as:
  - Segments in Transaction Traces
  - Span Events in Distributed Traces
  - Special custom attributes on Transaction Events

  > #### Warning {: .error}
  >
  > Traced functions will *not* be tail-call-recursive. **Don't use this for recursive functions**.

  #### Example

  Trace a function:

  ```elixir
  defmodule MyModule do
    use NewRelic.Tracer

    @trace :my_function
    def my_function do
      # Will report as `MyModule.my_function/0`
    end

    @trace :alias
    def my_function do
      # Will report as `MyModule.my_function:alias/0`
    end
  end
  ```

  #### Arguments

  By default, arguments are inspected and recorded along with traces. You can opt-out of function argument tracing on individual tracers:

  ```elixir
  defmodule SecretModule do
    use NewRelic.Tracer

    @trace {:login, args: false}
    def login(username, password) do
      # do something secret...
    end
  end
  ```

  This will prevent the argument values from becoming part of Transaction Traces.

  This may also be configured globally via `Application` config. See `NewRelic.Config` for details.

  #### External Service calls

  > #### Finch {: .warning}
  >
  > `Finch` requests are auto-instrumented, so you don't need to use `category: :external` tracers or call `set_span` if you use `Finch`.
  > You may still want to use a normal tracer for functions that make HTTP requests if they do additional work worth instrumenting.
  > Automatic `Finch` instrumentation can not inject Distributed Trace headers, so that must still be done manually.

  To manually instrument External Service calls you must give the trace annotation a category.

  You may also call `NewRelic.set_span/2` to provide better naming for metrics & spans, and additionally annotate the outgoing HTTP headers with the Distributed Tracing context to track calls across services.

  ```elixir
  defmodule MyExternalService do
    use NewRelic.Tracer

    @trace {:request, category: :external}
    def request(method, url, headers) do
      NewRelic.set_span(:http, url: url, method: method, component: "HttpClient")
      headers ++ NewRelic.distributed_trace_headers(:http)
      HttpClient.request(method, url, headers)
    end
  end
  ```
  """

  defmacro __using__(_args) do
    quote do
      require NewRelic
      require NewRelic.Tracer.Macro
      require NewRelic.Tracer.Report
      Module.register_attribute(__MODULE__, :nr_tracers, accumulate: true)
      Module.register_attribute(__MODULE__, :nr_last_tracer, accumulate: false)
      @before_compile NewRelic.Tracer.Macro
      @on_definition NewRelic.Tracer.Macro
    end
  end
end
