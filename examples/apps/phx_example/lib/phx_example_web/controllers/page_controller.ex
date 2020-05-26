defmodule PhxExampleWeb.PageController do
  use PhxExampleWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def error(_, _) do
    raise "BAD"
  end
end
