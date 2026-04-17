defmodule CadenceWeb.OperatorHomeController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    conn
    |> assign(:nav_context, :operator)
    |> put_layout(html: {CadenceWeb.Layouts, :sidebar})
    |> render(:show)
  end
end
