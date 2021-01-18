defmodule PhxExampleWeb.PageController do
  use PhxExampleWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def error(_, _) do
    IO.inspect {:raise, BAD}
    raise "BAD"
  end
end
