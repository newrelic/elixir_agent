defmodule PhxExampleWeb.PageController do
  use PhxExampleWeb, :controller

  def index(conn, _params) do
    Process.sleep(300)
    render(conn, :index)
  end

  def error(_, _) do
    raise "BAD"
  end
end
