defmodule PhxExampleWeb.ErrorView do
  use PhxExampleWeb, :view

  def render("500.html", _assigns) do
    "Opps, Internal Server Error"
  end

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
