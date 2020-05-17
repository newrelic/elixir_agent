defmodule PhxExampleWeb.Router do
  use PhxExampleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  scope "/", PhxExampleWeb do
    pipe_through :browser

    get "/", PageController, :index
  end
end
