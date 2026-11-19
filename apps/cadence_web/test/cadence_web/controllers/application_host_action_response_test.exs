defmodule CadenceWeb.ApplicationHostActionResponseTest do
  @moduledoc """
  A failed application-host action is answered ONCE (#230). Before the fix the problem was sent
  from inside the idempotency closure and then the outer path sent 409 action_indeterminate on
  the same request: two responses on one keep-alive connection, so the browser read the 409 as
  its NEXT request's answer, and the ledger recorded "may have executed" for an action that
  never ran (11-18, the comms routing form).
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @catalog_suffix "/api/cadence/application-host/v1/missions"

  setup do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, display_name: "Routing Mission")
    member_conn = TestFixtures.member_conn(user)
    catalog_conn = get(member_conn, @catalog_suffix <> "/#{mission.mission_id}/catalog")

    %{
      mission: mission,
      catalog_conn: catalog_conn,
      catalog: json_response(catalog_conn, 200),
      scope: %{
        "organizationId" => organization.organization_id,
        "missionId" => mission.mission_id,
        "spacecraftId" => nil
      }
    }
  end

  for action <- ["validate", "save"] do
    test "a failed #{action} sends exactly one 422, stores it as failed, and replays it", c do
      action = unquote(action)
      key = "routing-#{action}-#{System.unique_integer([:positive])}"

      conn = post_action(c, key, action, %{"routing_rule" => %{"display_name" => ""}})

      # Exactly one response on the wire for this request (the test adapter records each send).
      assert [{422, body}] = sent_responses(conn)

      assert %{"code" => code, "schema" => "cadence.application-host-problem.v1"} =
               Jason.decode!(body)

      refute code == "action_indeterminate"
      assert conn.status == 422

      # The ledger records a FAILED action with that 422, not "may have executed".
      assert [%{state: "failed", response_status: 422}] = ledger_rows(c.mission, action)

      # The same idempotency key replays the same 422, once.
      replay = post_action(c, key, action, %{"routing_rule" => %{"display_name" => ""}})
      assert [{422, ^body}] = sent_responses(replay)
    end
  end

  defp post_action(c, key, action, params) do
    c.catalog_conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cadence-poc-session", c.catalog["session"]["sessionId"])
    |> put_req_header("x-csrf-token", c.catalog["session"]["csrfToken"])
    |> put_req_header("idempotency-key", key)
    |> post(
      @catalog_suffix <> "/#{c.mission.mission_id}/actions",
      Jason.encode!(%{
        "applicationKey" => "comms",
        "applicationVersion" => 1,
        "surfaceId" => "routing_new",
        "surfaceVersion" => 1,
        "actionId" => action,
        "params" => params,
        "scope" => c.scope
      })
    )
  end

  # Every response the test adapter sent for this conn's request, oldest first.
  defp sent_responses(%Plug.Conn{adapter: {Plug.Adapters.Test.Conn, %{ref: ref}}}) do
    collect(ref, [])
  end

  defp collect(ref, acc) do
    receive do
      {^ref, {status, _headers, body}} -> collect(ref, [{status, body} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp ledger_rows(mission, action) do
    Repo.all(
      from(row in "federated_application_action_idempotencies",
        where:
          row.mission_id == ^mission.mission_id and row.surface_id == "routing_new" and
            row.operation == ^action,
        select: %{state: row.state, response_status: row.response_status}
      )
    )
  end
end
