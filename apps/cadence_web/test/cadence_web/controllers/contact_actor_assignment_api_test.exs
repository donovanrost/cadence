defmodule CadenceWeb.ContactActorAssignmentApiTest do
  @moduledoc "DECISIONS #32: contact action actors come only from the authenticated scope."
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.ControlPlaneApiFixtures

  setup %{conn: conn} do
    %{conn: conn, api_token: token, organization_id: org, mission_id: mission} = bootstrap(conn)
    %{conn: conn, token: token, base: "/api/organizations/#{org}/missions/#{mission}"}
  end

  for {path, envelope} <- [
        {"/scheduled_contacts/sc-1/cancel", "cancellation"},
        {"/realized_contacts/rc-1/end_early", "termination"}
      ] do
    test "#{path} refuses a client actor", c do
      conn =
        c.conn
        |> authorize(c.token)
        |> post(c.base <> unquote(path), %{
          unquote(envelope) => %{"actor" => %{"user_id" => "someone-else"}}
        })

      assert %{"errors" => [%{"field" => "actor", "reason" => "actor_not_assignable"}]} =
               json_response(conn, 422)
    end
  end
end
