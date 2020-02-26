if Code.ensure_loaded?(HTTPoison) do
  defmodule NewRelic.Instrumented.HTTPoison.Base do
    @moduledoc """
    To track outbound requests as part of a Distributed Trace, an additional request
    header needs to be added.

    This macro adds in the distributed_trace_header to all http calls
    and wraps the calls in a span.

    This module mirrors the interface of `HTTPoison.Base`.

    Instead of:
    `use HTTPoison.Base`

    Use:
    `use NewRelic.Instrumented.HTTPoison.Base`
    """

    defmacro __using__(_opts) do
      quote do
        use NewRelic.Tracer
        use HTTPoison.Base

        def instrument(method, url, headers) do
          NewRelic.set_span(:http, url: url, method: method, component: "HTTPoison")
          headers ++ NewRelic.distributed_trace_headers(:http)
        end

        @impl HTTPoison.Base
        @trace {:get, category: :external}
        def get(url, headers \\ [], options \\ []) do
          headers = instrument("GET", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:get!, category: :external}
        def get!(url, headers \\ [], options \\ []) do
          headers = instrument("GET", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:put, category: :external}
        def put(url, body \\ "", headers \\ [], options \\ []) do
          headers = instrument("PUT", url, headers)
          super(url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:put!, category: :external}
        def put!(url, body \\ "", headers \\ [], options \\ []) do
          headers = instrument("PUT", url, headers)
          super(url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:head, category: :external}
        def head(url, headers \\ [], options \\ []) do
          headers = instrument("HEAD", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:head!, category: :external}
        def head!(url, headers \\ [], options \\ []) do
          headers = instrument("HEAD", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:post, category: :external}
        def post(url, body, headers \\ [], options \\ []) do
          headers = instrument("POST", url, headers)
          super(url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:post!, category: :external}
        def post!(url, body, headers \\ [], options \\ []) do
          headers = instrument("POST", url, headers)
          super(url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:patch, category: :external}
        def patch(url, body, headers \\ [], options \\ []) do
          headers = instrument("PATCH", url, headers)
          super(url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:patch!, category: :external}
        def patch!(url, body, headers \\ [], options \\ []) do
          headers = instrument("PATCH", url, headers)
          super(url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:delete, category: :external}
        def delete(url, headers \\ [], options \\ []) do
          headers = instrument("DELETE", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:delete!, category: :external}
        def delete!(url, headers \\ [], options \\ []) do
          headers = instrument("DELETE", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:options, category: :external}
        def options(url, headers \\ [], options \\ []) do
          headers = instrument("OPTIONS", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:options!, category: :external}
        def options!(url, headers \\ [], options \\ []) do
          headers = instrument("OPTIONS", url, headers)
          super(url, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:request, category: :external}
        def request(method, url, body \\ "", headers \\ [], options \\ []) do
          headers = instrument(String.upcase(to_string(method)), url, headers)
          super(method, url, body, headers, options)
        end

        @impl HTTPoison.Base
        @trace {:request!, category: :external}
        def request!(method, url, body \\ "", headers \\ [], options \\ []) do
          headers = instrument(String.upcase(to_string(method)), url, headers)
          super(method, url, body, headers, options)
        end
      end
    end
  end
end
