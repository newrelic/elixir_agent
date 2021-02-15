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

    #### Notes:

    * If you need to pattern match against a result, note that the structs that come back are
    the original `HTTPoison` structs.

    ```elixir
    # Match against the full struct name
    {:ok, %Elixir.HTTPoison.Response{body: body}} = HTTPoison.get("http://www.example.com")

    # Match against it with a raw map
    {:ok, %{body: body}} = HTTPoison.get("http://www.example.com")
    ```
    """

    defp instrument(method, url, headers) do
      NewRelic.set_span(:http, url: url, method: method, component: "HTTPoison")
      headers ++ NewRelic.distributed_trace_headers(:http)
    end

    @trace {:get, category: :external}
    def get(url, headers \\ [], options \\ []) do
      headers = instrument("GET", url, headers)
      apply(HTTPoison, :get, [url, headers, options])
    end

    @trace {:get!, category: :external}
    def get!(url, headers \\ [], options \\ []) do
      headers = instrument("GET", url, headers)
      apply(HTTPoison, :get!, [url, headers, options])
    end

    @trace {:put, category: :external}
    def put(url, body \\ "", headers \\ [], options \\ []) do
      headers = instrument("PUT", url, headers)
      apply(HTTPoison, :put, [url, body, headers, options])
    end

    @trace {:put!, category: :external}
    def put!(url, body \\ "", headers \\ [], options \\ []) do
      headers = instrument("PUT", url, headers)
      apply(HTTPoison, :put!, [url, body, headers, options])
    end

    @trace {:head, category: :external}
    def head(url, headers \\ [], options \\ []) do
      headers = instrument("HEAD", url, headers)
      apply(HTTPoison, :head, [url, headers, options])
    end

    @trace {:head!, category: :external}
    def head!(url, headers \\ [], options \\ []) do
      headers = instrument("HEAD", url, headers)
      apply(HTTPoison, :head!, [url, headers, options])
    end

    @trace {:post, category: :external}
    def post(url, body, headers \\ [], options \\ []) do
      headers = instrument("POST", url, headers)
      apply(HTTPoison, :post, [url, body, headers, options])
    end

    @trace {:post!, category: :external}
    def post!(url, body, headers \\ [], options \\ []) do
      headers = instrument("POST", url, headers)
      apply(HTTPoison, :post!, [url, body, headers, options])
    end

    @trace {:patch, category: :external}
    def patch(url, body, headers \\ [], options \\ []) do
      headers = instrument("PATCH", url, headers)
      apply(HTTPoison, :patch, [url, body, headers, options])
    end

    @trace {:patch!, category: :external}
    def patch!(url, body, headers \\ [], options \\ []) do
      headers = instrument("PATCH", url, headers)
      apply(HTTPoison, :patch!, [url, body, headers, options])
    end

    @trace {:delete, category: :external}
    def delete(url, headers \\ [], options \\ []) do
      headers = instrument("DELETE", url, headers)
      apply(HTTPoison, :delete, [url, headers, options])
    end

    @trace {:delete!, category: :external}
    def delete!(url, headers \\ [], options \\ []) do
      headers = instrument("DELETE", url, headers)
      apply(HTTPoison, :delete!, [url, headers, options])
    end

    @trace {:options, category: :external}
    def options(url, headers \\ [], options \\ []) do
      headers = instrument("OPTIONS", url, headers)
      apply(HTTPoison, :options, [url, headers, options])
    end

    @trace {:options!, category: :external}
    def options!(url, headers \\ [], options \\ []) do
      headers = instrument("OPTIONS", url, headers)
      apply(HTTPoison, :options!, [url, headers, options])
    end

    @trace {:request, category: :external}
    def request(method, url, body \\ "", headers \\ [], options \\ []) do
      headers = instrument(String.upcase(to_string(method)), url, headers)
      apply(HTTPoison, :request, [method, url, body, headers, options])
    end

    @trace {:request!, category: :external}
    def request!(method, url, body \\ "", headers \\ [], options \\ []) do
      headers = instrument(String.upcase(to_string(method)), url, headers)
      apply(HTTPoison, :request!, [method, url, body, headers, options])
    end
  end
end
