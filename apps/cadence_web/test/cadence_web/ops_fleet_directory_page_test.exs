defmodule CadenceWeb.OpsFleetDirectoryPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, FleetPlanningPolicies, FleetPlanningRuns}
  alias Cadence.FleetStartFixtures
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/directory-contribution-check.mjs",
              __DIR__
            )
  @start ~U[2026-07-17 04:00:00Z]

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    craft =
      Spacecraft.new(%{
        spacecraft_id: Cadence.Ids.new("spacecraft"),
        mission_id: mission.mission_id,
        display_name: "Fleet member"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, craft)

    {:ok, policy, version} =
      FleetPlanningPolicies.create(scope, mission.mission_id, FleetStartFixtures.policy_attrs())

    {:ok, _, _, _} =
      FleetPlanningPolicies.approve(
        scope,
        mission.mission_id,
        policy.fleet_planning_policy_id,
        version.version,
        version.content_sha256,
        "Reviewed"
      )

    {:ok, _, _} =
      ContactRequirements.create(
        scope,
        mission.mission_id,
        FleetStartFixtures.requirement_attrs(%{spacecraft_id: craft.spacecraft_id})
      )

    c = %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/planning"
    }

    {:ok, run, _} = create_run(c)
    Map.put(c, :run, run)
  end

  test "host owns placement and the real producer renders through the public contribution", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "planning.fleet-directory"
    assert original["slot"] == "ops.page"
    assert original["status"] == "ready"
    assert [%{"id" => id, "phase" => "queued"}] = original["data"]["runs"]["entries"]
    assert id == c.run.fleet_planning_run_id

    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(original)], stderr_to_stdout: true)

    assert status == 0, output
    assert read(view, c.path, original)["snapshot"] == original
    assert {:ok, run} = FleetPlanningRuns.fetch(c.org.organization_id, c.mission.mission_id, id)
    assert run.phase == :queued
    # Reads do not replace the bootstrap or turn into planning actions.
    assert page(view) == original

    render_hook(view, "host:ops-page", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"],
      "event" => "continue",
      "input" => %{}
    })

    assert_reply(view, %{ok: false})
  end

  test "read recovery returns fresh evidence under captured page selectors", c do
    for _ <- 1..25, do: create_run(c)
    path = c.path <> "?page=2&state=queued"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["data"]["query"] == %{"page" => 2, "state" => "queued"}
    assert length(original["data"]["runs"]["entries"]) == 1
    {:ok, _, _} = create_run(c)
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["token"] == original["token"]
    assert refreshed["data"]["query"] == original["data"]["query"]
    assert length(refreshed["data"]["runs"]["entries"]) == 2
    assert page(view) == original
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    assert read(view, path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
    refute page(view)["token"] == original["token"]
    assert read(view, path, original)["ok"] == false
  end

  test "unknown identities, page tokens, paths and injected queries never authorize a read", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    for override <- [
          %{"id" => "unregistered"},
          %{"token" => Ecto.UUID.generate()},
          %{"path" => c.path <> "?page=2"},
          %{"input" => %{"page" => 2}},
          %{"mission_id" => "foreign"}
        ] do
      request =
        Map.merge(
          %{"path" => c.path, "id" => original["id"], "token" => original["token"]},
          override
        )

      render_hook(view, "host:ops-page:read", request)
      assert_reply(view, %{ok: false})
    end

    assert page(view) == original
  end

  test "invalid queries preserve host navigation with an unavailable contribution", c do
    {:ok, view, _} = live(c.conn, c.path <> "?page=0")
    assert has_element?(view, "#application-shell")
    assert page(view)["status"] == "unavailable"
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    assert page(view)["status"] == "ready"
  end

  test "revoked sessions cannot refresh a previously admitted directory", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"]
    })

    assert_redirect(view, "/sign-in")
  end

  defp create_run(c),
    do:
      FleetPlanningRuns.create(c.scope, c.mission.mission_id, %{
        horizon_start: @start,
        horizon_end: DateTime.add(@start, 14_400, :second)
      })

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, original) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
