defmodule PhxExampleWeb do
  def controller do
    quote do
      use Phoenix.Controller, namespace: PhxExampleWeb

      import Plug.Conn
      alias PhxExampleWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/phx_example_web/templates",
        namespace: PhxExampleWeb
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
