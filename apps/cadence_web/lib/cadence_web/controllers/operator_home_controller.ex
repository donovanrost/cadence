defmodule CadenceWeb.OperatorHomeController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    conn
    |> assign(:nav_context, :operator)
    |> assign(:nav_item, :operator_home)
    |> put_layout(html: {CadenceWeb.Layouts, :sidebar})
    |> render(:show)
  end
end
