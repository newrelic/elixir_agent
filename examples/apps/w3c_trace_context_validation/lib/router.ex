defmodule W3cTraceContextValidation.Router do
  use Plug.Router
  use NewRelic.Tracer

  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)

  plug(:match)
  plug(:dispatch)

  post "/test" do
    directions = conn.body_params["_json"]

    for %{"url" => url, "arguments" => arguments} <- directions do
      request(url, arguments)
    end

    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  @trace {:request, category: :external}
  def request(url, arguments) do
    NewRelic.set_span(:http, url: url, method: :post, component: "HTTPoison")

    HTTPoison.post(
      url,
      Jason.encode!(arguments),
      NewRelic.distributed_trace_headers(:http)
    )
  end
end
