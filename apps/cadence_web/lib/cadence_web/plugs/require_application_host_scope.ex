defmodule CadenceWeb.Plugs.RequireApplicationHostScope do
  @moduledoc false

  import Plug.Conn

  alias Cadence.Auth.Scope

  @problem_schema "cadence.application-host-problem.v1"

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_scope: %Scope{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{
      "schema" => @problem_schema,
      "code" => "unauthenticated",
      "message" => "Authentication is required for application-host requests."
    })
    |> halt()
  end
end
