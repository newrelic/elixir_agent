defmodule PhxExampleWeb.PageController do
  use PhxExampleWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
