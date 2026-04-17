defmodule CadenceWeb.OperatorHomeController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    conn
    |> put_layout(html: {CadenceWeb.Layouts, :sidebar})
    |> render(:show)
  end
end
