defmodule PhxExampleWeb.Router do
  use PhxExampleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhxExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/phx", PhxExampleWeb do
    pipe_through :browser

    get "/error", PageController, :error
    get "/:foo", PageController, :index
  end
end
