defmodule CadenceWeb.OpsFleetWorkflowPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, FleetPlanningRuns}
  alias Cadence.{FleetRunFixtures, FleetStartFixtures}
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/workflow-contribution-check.mjs",
              __DIR__
            )

  setup do
    c = FleetRunFixtures.setup_run()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, c.organization, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: c.organization_id,
        organization_membership: membership
      })

    Map.merge(c, %{
      scope: scope,
      user: user,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{c.mission_id}/ops/planning"
    })
  end

  test "native creation is bound to the page preview and its real receipt survives public contribution admission",
       c do
    path = c.path <> "/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["id"] == "planning.fleet-start"
    assert original["status"] == "ready"
    window = FleetStartFixtures.params()["fleet_run"]
    input = native(%{snapshot: original, window: window, action: "validate-fleet-run"})

    assert action(view, path, original, "create-fleet-run", %{
             "fleet_run" => input["fleet_run"],
             "evidence" => %{}
           })["snapshot"]["status"] == "rejected"

    preview = action(view, path, original, "validate-fleet-run", input)["snapshot"]
    assert is_binary(preview["receiptId"])

    create =
      native(%{snapshot: original, window: window, review: preview, action: "create-fleet-run"})

    assert create["evidence"] == preview["result"]["review"]["evidence"]

    assert action(
             view,
             path,
             original,
             "create-fleet-run",
             put_in(create, ["evidence", "policy_version"], 99)
           )["snapshot"]["status"] == "rejected"

    receipt = action(view, path, original, "create-fleet-run", create)["snapshot"]
    assert receipt["result"]["evidence"] == create["evidence"]
    assert receipt["result"]["lifecycleState"] == "queued"

    assert native(%{
             snapshot: original,
             window: window,
             review: preview,
             receipt: receipt,
             action: "create-fleet-run"
           }) == create

    {:ok, run} =
      FleetPlanningRuns.fetch(
        c.organization_id,
        c.mission_id,
        receipt["result"]["fleetPlanningRunId"]
      )

    assert run.phase == :queued

    assert action(view, path, original, "create-fleet-run", create)["snapshot"]["status"] ==
             "rejected"

    assert read(view, path, original)["snapshot"]["status"] == "ready"

    assert action(view, path, original, "create-fleet-run", create)["snapshot"]["status"] ==
             "rejected"

    assert page(view) == original
  end

  test "native run continuation uses captured evidence while refresh remains read-only", c do
    path = run_path(c)
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["id"] == "planning.fleet-run"
    assert original["context"]["resourceId"] == c.run.fleet_planning_run_id
    assert read(view, path, original)["snapshot"] == original

    {:ok, before} =
      FleetPlanningRuns.fetch(c.organization_id, c.mission_id, c.run.fleet_planning_run_id)

    assert before.phase == :queued
    input = native(%{snapshot: original, action: "refresh-fleet-run"})
    assert input["evidence"] == original["data"]["evidence"]
    receipt = action(view, path, original, "refresh-fleet-run", input)["snapshot"]
    assert native(%{snapshot: original, action: "refresh-fleet-run", receipt: receipt}) == input
    assert receipt["result"]["outcome"] == "continued"
    assert receipt["result"]["evidence"] == input["evidence"]

    assert action(view, path, original, "refresh-fleet-run", input)["snapshot"]["status"] ==
             "rejected"

    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["data"]["phase"] == "finished"
    assert refreshed["data"]["can_continue"] == false
    assert page(view) == original
  end

  test "native repair creates one queued successor with exact reviewed commitments", c do
    c = FleetRunFixtures.repairable(c)
    path = run_path(c)
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["data"]["repair"]["available"]
    window = FleetStartFixtures.params()["fleet_run"] |> Map.delete("include_recurring")
    input = native(%{snapshot: original, action: "repair-fleet-run", window: window})
    assert input["evidence"] == original["data"]["repair"]["evidence"]
    receipt = action(view, path, original, "repair-fleet-run", input)["snapshot"]

    assert native(%{
             snapshot: original,
             action: "repair-fleet-run",
             window: window,
             receipt: receipt
           }) == input

    assert receipt["result"]["outcome"] == "repair_created"

    {:ok, run} =
      FleetPlanningRuns.fetch(
        c.organization_id,
        c.mission_id,
        receipt["result"]["fleetPlanningRunId"]
      )

    assert run.phase == :queued
    assert run.source_fleet_planning_run_id == c.run.fleet_planning_run_id
    assert run.input_document["creation_review"] == input["evidence"]

    assert action(view, path, original, "repair-fleet-run", input)["snapshot"]["status"] ==
             "rejected"
  end

  test "changed creation inputs consume an unconfirmed submission without duplicating a run", c do
    path = c.path <> "/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    input = FleetStartFixtures.params()
    preview = action(view, path, original, "validate-fleet-run", input)["snapshot"]
    create = Map.put(input, "evidence", preview["result"]["review"]["evidence"])

    {:ok, _, _} =
      ContactRequirements.create(c.scope, c.mission_id, FleetStartFixtures.requirement_attrs())

    before = length(FleetPlanningRuns.list(c.organization_id, c.mission_id))

    assert action(view, path, original, "create-fleet-run", create)["snapshot"]["status"] ==
             "unconfirmed"

    assert action(view, path, original, "create-fleet-run", create)["snapshot"]["status"] ==
             "rejected"

    assert length(FleetPlanningRuns.list(c.organization_id, c.mission_id)) == before
  end

  test "captured path, query, resource and token reject substitutions and expire after navigation",
       c do
    path = run_path(c) <> "?requirements_page=2"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["data"]["query"]["requirements_page"] == 2
    assert read(view, path, original)["snapshot"]["data"]["query"] == original["data"]["query"]
    request = %{"path" => path, "id" => original["id"], "token" => original["token"]}

    for changed <- [
          %{"path" => run_path(c)},
          %{"token" => Ecto.UUID.generate()},
          %{"id" => "planning.fleet-start"},
          %{"input" => %{"requirements_page" => 1}}
        ] do
      render_hook(view, "host:ops-page:read", Map.merge(request, changed))
      assert_reply(view, %{ok: false})
    end

    input = %{"fleet_planning_run_id" => "foreign", "evidence" => original["data"]["evidence"]}

    assert action(view, path, original, "refresh-fleet-run", input)["snapshot"]["status"] ==
             "rejected"

    assert action(view, path, original, "create-fleet-run", input)["ok"] == false
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    assert read(view, path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
    refute page(view)["token"] == original["token"]
    assert action(view, path, original, "refresh-fleet-run", input)["ok"] == false
  end

  test "malformed run queries retain the authenticated host and cannot perform actions", c do
    path = run_path(c) <> "?requirements_page=0"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert has_element?(view, "#application-shell")
    assert original["status"] == "unavailable"

    assert action(view, path, original, "refresh-fleet-run", %{})["snapshot"]["status"] ==
             "rejected"

    render_hook(view, "host:context", %{"path" => run_path(c)})
    assert_reply(view, %{ok: true})
    assert page(view)["status"] == "ready"
  end

  test "a revoked session cannot use a previously admitted action", c do
    path = run_path(c)
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"],
      "event" => "refresh-fleet-run",
      "input" => %{
        "fleet_planning_run_id" => c.run.fleet_planning_run_id,
        "evidence" => original["data"]["evidence"]
      }
    })

    assert_redirect(view, "/sign-in")

    {:ok, run} =
      FleetPlanningRuns.fetch(c.organization_id, c.mission_id, c.run.fleet_planning_run_id)

    assert run.phase == :queued
  end

  defp run_path(c), do: c.path <> "/runs/" <> c.run.fleet_planning_run_id

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, page) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp native(supplied) do
    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, payload] = Regex.run(~r/FLEET_CONTRIBUTION_INPUT=([^\n]+)/, output)
    Jason.decode!(payload)
  end
end
