defmodule NewRelic.Tracer do
  @moduledoc """
  Function Tracing

  To enable function tracing in a particular module, `use NewRelic.Tracer`,
  and annotate the functions you want to `@trace`.

  Traced functions will report as:
  - Segments in Transaction Traces
  - Span Events in Distributed Traces
  - Special custom attributes on Transaction Events

  #### Notes:

  * Traced functions will *not* be tail-call-recursive. **Don't use this for recursive functions**.

  #### Example

  ```elixir
  defmodule MyModule do
    use NewRelic.Tracer

    @trace :func
    def func do
      # Will report as `MyModule.func/0`
    end
  end
  ```

  #### Categories

  To categorize External Service calls you must give the trace annotation a category.

  You may also call `NewRelic.set_span` to provide better naming for metrics & spans, and additonally annotate the outgoing HTTP headers with the Distributed Tracing context to track calls across services.

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

  This will:
  * Post `External` metrics to APM
  * Add custom attributes to Transaction events:
    - `external_call_count`
    - `external_duration_ms`
    - `external.MyExternalService.query.call_count`
    - `external.MyExternalService.query.duration_ms`

  Transactions that call the traced `ExternalService` functions will contain `external_call_count` attribute

  ```elixir
  get "/endpoint" do
    ExternalService.request(:get, url, headers)
    send_resp(conn, 200, "ok")
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
