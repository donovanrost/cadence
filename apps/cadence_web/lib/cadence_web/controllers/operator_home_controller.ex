defmodule CadenceWeb.OperatorHomeController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    render(conn, :show)
  end
end
