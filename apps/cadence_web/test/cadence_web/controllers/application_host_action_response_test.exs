defmodule CadenceWeb.ApplicationHostActionResponseTest do
  @moduledoc """
  A failed application-host action is answered ONCE (#230). Before the fix the problem was sent
  from inside the idempotency closure and then the outer path sent 409 action_indeterminate on
  the same request: two responses on one keep-alive connection, so the browser read the 409 as
  its NEXT request's answer, and the ledger recorded "may have executed" for an action that
  never ran.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @bridge_suffix "/api/cadence/application-host/v1/missions"
  @action "save_configuration"

  setup do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{user: user, organization: organization, organization_membership: membership})

    host = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
    assert {:ok, _} = ApplicationInstallations.install(scope, host, "telemetry_decom")
    member_conn = TestFixtures.member_conn(user)

    # The console's surface host mints the bridge session (host session id, CSRF token, pinned scope).
    catalog_conn =
      get(
        member_conn,
        "/api/v1/missions/#{mission.mission_id}/apps/telemetry_decom/surfaces/manage/host?spacecraft_id=#{spacecraft.spacecraft_id}"
      )

    %{
      mission: mission,
      spacecraft: spacecraft,
      catalog_conn: catalog_conn,
      catalog: json_response(catalog_conn, 200)["data"]["catalog"],
      scope: %{
        "organizationId" => organization.organization_id,
        "missionId" => mission.mission_id,
        "spacecraftId" => spacecraft.spacecraft_id
      }
    }
  end

  test "a failed configuration save sends exactly one 422, stores it as failed, and replays it",
       c do
    key = "telemetry-decom-#{System.unique_integer([:positive])}"

    conn = post_action(c, key)

    # Exactly one response on the wire for this request (the test adapter records each send).
    assert [{422, body}] = sent_responses(conn)

    assert %{"code" => code, "schema" => "cadence.application-host-problem.v1"} =
             Jason.decode!(body)

    refute code == "action_indeterminate"
    assert conn.status == 422

    assert [%{state: "failed", response_status: 422}] = ledger_rows(c.mission)

    replay = post_action(c, key)
    assert [{422, ^body}] = sent_responses(replay)
  end

  defp post_action(c, key) do
    c.catalog_conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cadence-poc-session", c.catalog["session"]["sessionId"])
    |> put_req_header("x-csrf-token", c.catalog["session"]["csrfToken"])
    |> put_req_header("idempotency-key", key)
    |> post(
      @bridge_suffix <>
        "/#{c.mission.mission_id}/spacecraft/#{c.spacecraft.spacecraft_id}/actions",
      Jason.encode!(%{
        "applicationKey" => "telemetry_decom",
        "applicationVersion" => 1,
        "surfaceId" => "manage",
        "surfaceVersion" => 1,
        "actionId" => @action,
        "input" => %{},
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

  defp ledger_rows(mission) do
    Repo.all(
      from(row in "federated_application_action_idempotencies",
        where:
          row.mission_id == ^mission.mission_id and row.surface_id == "manage" and
            row.operation == @action,
        select: %{state: row.state, response_status: row.response_status}
      )
    )
  end
end
