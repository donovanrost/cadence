defmodule CadenceWeb.CommandingActorAssignmentApiTest do
  @moduledoc """
  DECISIONS #30: commanding actors (owner, requested_by, decided_by, enqueued_by, released_by)
  always come from the authenticated scope. A request that names one gets 422
  `actor_not_assignable`, so a client can't act as someone else or approve its own request as
  another user.
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
               "owner" => %{"actor_kind" => "service", "service_identity_id" => "svc-bootstrap"}
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

  test "stage submission refuses requested_by", c do
    refused(
      c,
      :post,
      "/command_stages/stage-x/submit",
      %{"submission" => %{"staged_command_item_ids" => ["item-1"], "requested_by" => @someone}},
      "requested_by"
    )
  end

  test "command request create refuses requested_by", c do
    refused(
      c,
      :post,
      "/command_requests",
      %{
        "command_request" => %{
          "source_endpoint_ref" => "ep-1",
          "mission_model_revision_id" => "rev-1",
          "command_id" => "cmd-1",
          "requested_by" => @someone
        }
      },
      "requested_by"
    )
  end

  test "approve and reject refuse decided_by", c do
    refused(
      c,
      :post,
      "/command_requests/req-1/approve",
      %{"approval" => %{"decided_by" => @someone}},
      "decided_by"
    )

    refused(
      c,
      :post,
      "/command_requests/req-1/reject",
      %{"rejection" => %{"decided_by" => @someone}},
      "decided_by"
    )
  end

  test "enqueue refuses enqueued_by", c do
    refused(
      c,
      :post,
      "/command_requests/req-1/enqueue",
      %{"queue_entry" => %{"enqueued_by" => @someone}},
      "enqueued_by"
    )
  end

  test "release refuses released_by", c do
    refused(
      c,
      :post,
      "/command_queue_entries/qe-1/release",
      %{"release_attempt" => %{"realized_contact_id" => "rc-1", "released_by" => @someone}},
      "released_by"
    )
  end

  test "an explicit null actor is refused too", c do
    refused(
      c,
      :post,
      "/command_requests/req-1/approve",
      %{"approval" => %{"decided_by" => nil}},
      "decided_by"
    )
  end
end
