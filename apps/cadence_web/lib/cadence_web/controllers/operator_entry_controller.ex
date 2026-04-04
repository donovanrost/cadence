defmodule CadenceWeb.OperatorEntryController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    redirect(conn, to: "/operator")
  end
end
