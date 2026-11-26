defmodule CadenceWeb.CommandingActorAssignmentApiTest do
  @moduledoc """
  DECISIONS #30: a commanding actor (a stage's owner)
  always comes from the authenticated scope. A request that names one gets 422
  `actor_not_assignable`, so a client can't act as someone else.
  """
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.ControlPlaneApiFixtures

  @someone %{"actor_kind" => "user", "user_id" => "someone-else"}

  setup %{conn: conn} do
    %{conn: conn, api_token: token, organization_id: org, mission_id: mission} = bootstrap(conn)
    %{conn: conn, token: token, base: "/api/organizations/#{org}/missions/#{mission}"}
  end

  defp refused(c, method, path, body, field) do
    conn = c.conn |> authorize(c.token) |> dispatch_json(method, c.base <> path, body)

    assert %{"errors" => [%{"field" => ^field, "reason" => "actor_not_assignable"}]} =
             json_response(conn, 422)
  end

  defp dispatch_json(conn, :post, path, body), do: post(conn, path, body)
  defp dispatch_json(conn, :patch, path, body), do: patch(conn, path, body)

  test "command stage create refuses a client owner and records the service as owner", c do
    refused(
      c,
      :post,
      "/command_stages",
      %{"command_stage" => %{"stage_name" => "S", "owner" => @someone}},
      "owner"
    )

    created =
      c.conn
      |> authorize(c.token)
      |> post(c.base <> "/command_stages", %{
        "command_stage" => %{"stage_name" => "S", "command_stage_id" => "stage-actor"}
      })
      |> json_response(201)

    assert %{
             "data" => %{
               # #465: REST names an actor as {kind, id, name}, never the stored document.
               "owner" => %{"kind" => "service", "id" => "svc-bootstrap"}
             }
           } =
             created

    refused(
      c,
      :patch,
      "/command_stages/stage-actor",
      %{"command_stage" => %{"owner" => @someone}},
      "owner"
    )
  end

  test "an explicit null actor is refused too", c do
    refused(
      c,
      :post,
      "/command_stages",
      %{"command_stage" => %{"stage_name" => "S", "owner" => nil}},
      "owner"
    )
  end
end
