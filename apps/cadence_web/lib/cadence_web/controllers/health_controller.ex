defmodule CadenceWeb.HealthController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    json(conn, %{data: %{status: "ok"}})
  end
end
