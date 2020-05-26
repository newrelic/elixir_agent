defmodule PhxExampleWeb.Router do
  use PhxExampleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  scope "/phx", PhxExampleWeb do
    pipe_through :browser

    get "/error", PageController, :error
    get "/:foo", PageController, :index
  end
end
