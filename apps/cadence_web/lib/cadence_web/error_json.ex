defmodule CadenceWeb.ErrorJSON do
  @moduledoc false

  def render("404.json", _assigns), do: %{error: %{code: "not_found"}}
  def render("500.json", _assigns), do: %{error: %{code: "internal_server_error"}}
end
