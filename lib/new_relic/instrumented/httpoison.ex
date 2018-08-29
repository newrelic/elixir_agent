if Code.ensure_loaded?(HTTPoison) do
  defmodule NewRelic.Instrumented.HTTPoison do
    use NewRelic.Tracer

    @moduledoc """
    To track outbound requests as part of a Distributed Trace, an additional request
    header needs to be added. Simply alias this module and use `HTTPoison` as normal,
    all your requests will be automatically instrumented.

    ```elixir
    alias NewRelic.Instrumented.HTTPoison
    HTTPoison.get("http://www.example.com")
    ```

    This module mirrors the interface of `HTTPoison`
    """

    defp instrument(method, url, headers) do
      NewRelic.set_span(:http, url: url, method: method, component: "HTTPoison")
      headers ++ NewRelic.create_distributed_trace_payload(:http)
    end

    @trace {:get, category: :external}
    def get(url, headers \\ [], options \\ []) do
      headers = instrument("GET", url, headers)
      HTTPoison.get(url, headers, options)
    end

    @trace {:get!, category: :external}
    def get!(url, headers \\ [], options \\ []) do
      headers = instrument("GET", url, headers)
      HTTPoison.get!(url, headers, options)
    end

    @trace {:put, category: :external}
    def put(url, body \\ "", headers \\ [], options \\ []) do
      headers = instrument("PUT", url, headers)
      HTTPoison.put(url, body, headers, options)
    end

    @trace {:put!, category: :external}
    def put!(url, body \\ "", headers \\ [], options \\ []) do
      headers = instrument("PUT", url, headers)
      HTTPoison.put!(url, body, headers, options)
    end

    @trace {:head, category: :external}
    def head(url, headers \\ [], options \\ []) do
      headers = instrument("HEAD", url, headers)
      HTTPoison.head(url, headers, options)
    end

    @trace {:head!, category: :external}
    def head!(url, headers \\ [], options \\ []) do
      headers = instrument("HEAD", url, headers)
      HTTPoison.head!(url, headers, options)
    end

    @trace {:post, category: :external}
    def post(url, body, headers \\ [], options \\ []) do
      headers = instrument("POST", url, headers)
      HTTPoison.post(url, body, headers, options)
    end

    @trace {:post!, category: :external}
    def post!(url, body, headers \\ [], options \\ []) do
      headers = instrument("POST", url, headers)
      HTTPoison.post!(url, body, headers, options)
    end

    @trace {:patch, category: :external}
    def patch(url, body, headers \\ [], options \\ []) do
      headers = instrument("PATCH", url, headers)
      HTTPoison.patch(url, body, headers, options)
    end

    @trace {:patch!, category: :external}
    def patch!(url, body, headers \\ [], options \\ []) do
      headers = instrument("PATCH", url, headers)
      HTTPoison.patch!(url, body, headers, options)
    end

    @trace {:delete, category: :external}
    def delete(url, headers \\ [], options \\ []) do
      headers = instrument("DELETE", url, headers)
      HTTPoison.delete(url, headers, options)
    end

    @trace {:delete!, category: :external}
    def delete!(url, headers \\ [], options \\ []) do
      headers = instrument("DELETE", url, headers)
      HTTPoison.delete!(url, headers, options)
    end

    @trace {:options, category: :external}
    def options(url, headers \\ [], options \\ []) do
      headers = instrument("OPTIONS", url, headers)
      HTTPoison.options(url, headers, options)
    end

    @trace {:options!, category: :external}
    def options!(url, headers \\ [], options \\ []) do
      headers = instrument("OPTIONS", url, headers)
      HTTPoison.options!(url, headers, options)
    end
  end
end
