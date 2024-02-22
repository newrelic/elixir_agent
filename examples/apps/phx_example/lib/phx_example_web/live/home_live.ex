defmodule PhxExampleWeb.HomeLive do
  use PhxExampleWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Home</h1>
      <p>Some content</p>
    </div>
    """
  end
end
