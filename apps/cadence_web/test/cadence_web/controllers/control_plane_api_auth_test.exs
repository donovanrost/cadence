defmodule CadenceWeb.ControlPlaneApiAuthTest do
  use CadenceWeb.ConnCase, async: true

  import CadenceWeb.ControlPlaneApiFixtures

  # #281: a REST bearer is always a service identity, and services never manage service
  # identities, so the REST endpoints are gone; people issue them in the console.
  test "the REST service identity endpoints no longer exist", %{conn: conn} do
    %{api_token: api_token, organization_id: organization_id} = bootstrap(conn)
    path = "/api/organizations/#{organization_id}/service_identities"

    body = %{
      "service_identity" => %{
        "display_name" => "Minted",
        "capabilities" => ["organization_admin"]
      }
    }

    assert conn |> authorize(api_token) |> get(path) |> response(404)
    assert conn |> authorize(api_token) |> post(path, body) |> response(404)
    assert [_bootstrap_only] = Cadence.Auth.list_service_identities(organization_id)
  end

  # #384 (director 11-19): the organization-level REST bearer routes are retired. A bearer is
  # always a service identity, and organization-level actions are a person's (#282).
  test "the organization read and the mission list and create answer 404 to a service", %{
    conn: conn
  } do
    %{api_token: api_token, organization_id: organization_id} = bootstrap(conn)
    base = "/api/organizations/#{organization_id}"
    before = Cadence.Missions.list_missions(organization_id)

    assert conn |> authorize(api_token) |> get(base) |> response(404)
    assert conn |> authorize(api_token) |> get(base <> "/missions") |> response(404)

    assert conn
           |> authorize(api_token)
           |> post(base <> "/missions", %{
             "mission" => %{
               "mission_id" => "mission-384",
               "slug" => "mission-384",
               "display_name" => "Mission 384"
             }
           })
           |> response(404)

    assert Cadence.Missions.list_missions(organization_id) == before
  end

  # #754 part 2 (#747, one API): commands are command groups' members, read through the console
  # API; the old REST command reads and the queue entry release are gone, with no alias.
  test "the old REST command endpoints answer 404", %{conn: conn} do
    %{api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    base = "/api/organizations/#{organization_id}/missions/#{mission_id}"

    for path <-
          ~w(/command_requests /command_requests/r-1 /command_approvals /command_approvals/a-1
             /command_queue_entries /command_queue_entries/q-1 /command_release_attempts
             /command_release_attempts/ra-1 /command_verifier_instances
             /command_verifier_instances/v-1) do
      assert conn |> authorize(api_token) |> get(base <> path) |> response(404), path
    end

    assert conn
           |> authorize(api_token)
           |> post(base <> "/command_queue_entries/q-1/release", %{
             "release_attempt" => %{"realized_contact_id" => "rc-1"}
           })
           |> response(404)
  end
end
