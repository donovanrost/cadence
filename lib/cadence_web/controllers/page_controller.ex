defmodule CadenceWeb.PageController do
  use CadenceWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
