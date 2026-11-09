defmodule CadenceWeb.ErrorJSON do
  @moduledoc false

  def render("404.json", _assigns), do: %{error: %{code: "not_found"}}
  def render("500.json", _assigns), do: %{error: %{code: "internal_server_error"}}

  def render("413.json", _assigns),
    do: %{error: %{code: "file_too_large", message: "The request body is too large."}}

  # Any other status renders its standard reason phrase as a snake_case code.
  def render(template, _assigns) do
    code =
      template
      |> Phoenix.Controller.status_message_from_template()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")

    %{error: %{code: code}}
  end
end
