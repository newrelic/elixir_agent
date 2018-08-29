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

  To categorize External Service calls, use this syntax:

  ```elixir
  defmodule MyExternalService do
    use NewRelic.Tracer
    @trace {:query, category: :external}
    def query(args) do
      # Make the call
    end
  end
  ```

  This will:
  * Post `External` metrics to APM
  * Add custom attributes to Transaction events:
    - `external_call_count`
    - `external_duration_ms`
    - `external.MyExternalService.query/0.call_count`
    - `external.MyExternalService.query/0.duration_ms`

  Transactions that call the traced `ExternalService` functions will contain `external_call_count` attribute

  ```elixir
  get "/endpoint" do
    ExternalService.query(2)
    send_resp(conn, 200, "ok")
  end
  ```
  """

  defmacro __using__(_args) do
    quote do
      require NewRelic.Tracer.Macro
      require NewRelic.Tracer.Report
      Module.register_attribute(__MODULE__, :nr_tracers, accumulate: true)
      Module.register_attribute(__MODULE__, :nr_last_tracer, accumulate: false)
      @before_compile NewRelic.Tracer.Macro
      @on_definition NewRelic.Tracer.Macro
    end
  end
end
