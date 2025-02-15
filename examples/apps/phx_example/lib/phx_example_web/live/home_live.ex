defmodule PhxExampleWeb.HomeLive do
  use PhxExampleWeb, :live_view

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:content, "stuff")

    {:ok, socket}
  end

  def handle_event("click", _params, socket) do
    socket =
      socket
      |> assign(:content, "clicked")

    Process.send_after(self(), :after, 1_000)
    {:noreply, socket}
  end

  def handle_info(:after, socket) do
    socket =
      socket
      |> assign(:content, "after")

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Home</h1>
      <p>Some content</p>
      <p><%= @content %></p>
      <div phx-click="click">Click me</div>
    </div>
    """
  end
end
