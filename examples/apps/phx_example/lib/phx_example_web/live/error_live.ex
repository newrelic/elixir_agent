defmodule PhxExampleWeb.ErrorLive do
  use PhxExampleWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1><%= @some_variable %></h1>
    </div>
    """
  end
end
