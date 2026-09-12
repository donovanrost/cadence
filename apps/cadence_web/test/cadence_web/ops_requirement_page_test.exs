defmodule CadenceWeb.OpsRequirementPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias Cadence.Reads.ApplicationSurfaces.Planning.RequirementDirectory
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures
  @now ~U[2027-01-01 00:00:00Z]
  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/contact-requirements/requirement-workflow-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :member)
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
        display_name: "Requirement spacecraft"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, craft)

    attrs = %{
      spacecraft_id: craft.spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(@now, 3600),
      latest_end: DateTime.add(@now, 28_800),
      success_measure: :minimum_duration,
      minimum_duration_seconds: 60,
      priority: :high,
      rationale: "Reviewed requirement"
    }

    {:ok, requirement, version} = ContactRequirements.create(scope, mission.mission_id, attrs)

    c = %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      craft: craft,
      attrs: attrs,
      requirement: requirement,
      version: version,
      conn: TestFixtures.member_conn(user),
      base: "/missions/#{mission.mission_id}/ops/requirements"
    }

    Map.put(c, :planning, planning(c))
  end

  test "semantic directory renders the public contribution and retains bounded captured reads",
       c do
    {:ok, view, _} = live(c.conn, c.base)
    original = page(view)
    assert original["id"] == "planning.requirement-directory"
    assert [%{"id" => id}] = original["data"]["requirements"]["entries"]
    assert id == c.requirement.contact_requirement_id
    assert native(%{snapshot: original}) == nil
    assert read(view, c.base, original)["snapshot"] == original
    assert page(view) == original
    assert action(view, c.base, original, "plan", %{})["ok"] == false

    for _ <- 1..25,
        do:
          assert({:ok, _, _} = ContactRequirements.create(c.scope, c.mission.mission_id, c.attrs))

    path = c.base <> "?page=2&state=active"
    {:ok, paged, _} = live(c.conn, path)
    next = page(paged)
    assert length(next["data"]["requirements"]["entries"]) == 1
    assert next["data"]["query"] == %{"page" => 2, "state" => "active"}
    assert read(paged, path, next)["snapshot"] == next

    assert length(
             Planner.list_runs(
               c.org.organization_id,
               c.mission.mission_id,
               c.requirement.contact_requirement_id
             )
           ) == 1
  end

  for event <- ~w(plan create-plan) do
    @event event
    test "native #{@event} completes through authenticated host and admits the actual receipt",
         c do
      path = review_path(c)
      {:ok, view, _} = live(c.conn, path)
      original = page(view)
      assert original["id"] == "planning.requirement-review"
      assert original["context"]["resourceId"] == c.requirement.contact_requirement_id
      [event, input] = native(%{snapshot: original, action: @event})
      assert event == @event
      receipt = action(view, path, original, event, input)["snapshot"]
      assert receipt["status"] == "completed"
      assert receipt["receipt"]["receiptId"]
      assert native(%{snapshot: original, action: @event, operation: receipt}) == [event, input]
      assert action(view, path, original, event, input)["snapshot"]["status"] == "rejected"
      recovered = read(view, path, original)["snapshot"]
      assert recovered["data"]["operation"] == receipt
      assert recovered["data"]["detail"]["query"] == original["data"]["detail"]["query"]
      assert page(view) == original
      assert_effect(c, @event, receipt, input)
    end
  end

  test "stale and foreign review evidence cannot start planning or create a proposal", c do
    path = review_path(c)
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    [_, input] = native(%{snapshot: original, action: "create-plan"})
    foreign = put_in(input, ["payload", "requirement_evidence", "mission_id"], "foreign")

    assert action(view, path, original, "create-plan", foreign)["snapshot"]["status"] ==
             "rejected"

    {:ok, _, _} =
      ContactRequirements.version(
        c.scope,
        c.mission.mission_id,
        c.requirement.contact_requirement_id,
        1,
        %{minimum_duration_seconds: 61}
      )

    stale = Map.put(input, "sequence", 2)
    assert action(view, path, original, "create-plan", stale)["snapshot"]["status"] == "rejected"
    assert ContactPlans.list(c.org.organization_id, c.mission.mission_id) == []
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["data"]["detail"]["requirement"]["version"] == 1
    assert refreshed["data"]["detail"]["requirement"]["current_version"] == 2

    assert refreshed["data"]["detail"]["selected_run"]["id"] ==
             c.planning.run.contact_planning_run_id
  end

  test "an initially current review pins its version without silently selecting a new search",
       c do
    path = c.base <> "/" <> c.requirement.contact_requirement_id
    {:ok, view, _} = live(c.conn, path)
    original = page(view)

    {:ok, _, _} =
      ContactRequirements.version(
        c.scope,
        c.mission.mission_id,
        c.requirement.contact_requirement_id,
        1,
        %{minimum_duration_seconds: 61}
      )

    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["data"]["detail"]["query"]["version"] == 1
    assert refreshed["data"]["detail"]["requirement"]["current_version"] == 2
    assert refreshed["data"]["detail"]["selected_run"] == nil
    assert page(view) == original
  end

  test "captured reads reject injected selectors, departed tokens and revoked sessions", c do
    path = review_path(c)
    {:ok, view, _} = live(c.conn, path)
    original = page(view)

    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"],
      "input" => %{"version" => 2}
    })

    assert_reply(view, %{ok: false})
    render_hook(view, "host:context", %{"path" => c.base})
    assert_reply(view, %{ok: true})
    assert read(view, path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
    current = page(view)
    refute current["token"] == original["token"]
    :ok = Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => current["id"],
      "token" => current["token"]
    })

    assert_redirect(view, "/sign-in")
  end

  test "unavailable pages preserve host navigation and cross-mission directory scopes fail closed",
       c do
    {:ok, invalid, _} = live(c.conn, c.base <> "?page=0")
    assert has_element?(invalid, "#application-shell")
    assert page(invalid)["status"] == "unavailable"
    {:ok, foreign, _} = live(c.conn, c.base <> "/foreign-requirement")
    assert page(foreign)["status"] == "unavailable"

    assert {:error, :scope_mismatch} =
             RequirementDirectory.load(
               %{c.scope | mission_id: "foreign"},
               c.mission.mission_id,
               %{}
             )
  end

  defp assert_effect(c, "plan", receipt, _) do
    id = receipt["receipt"]["result"]["planningRunId"]
    {:ok, run} = Planner.fetch_run(c.org.organization_id, c.mission.mission_id, id)
    assert run.contact_requirement_version == 1
    assert run.contact_requirement_id == c.requirement.contact_requirement_id

    assert length(
             Planner.list_runs(
               c.org.organization_id,
               c.mission.mission_id,
               c.requirement.contact_requirement_id
             )
           ) == 2
  end

  defp assert_effect(c, "create-plan", receipt, input) do
    id = receipt["receipt"]["result"]["contactPlanId"]
    {:ok, _, version} = ContactPlans.fetch(c.org.organization_id, c.mission.mission_id, id)
    assert version.selected_snapshot_ids == input["payload"]["selected_snapshot_ids"]
    assert version.planning_run_refs_document["runs"] == [c.planning.run.contact_planning_run_id]
    assert length(ContactPlans.list(c.org.organization_id, c.mission.mission_id)) == 1
  end

  defp review_path(c),
    do:
      c.base <>
        "/" <>
        c.requirement.contact_requirement_id <>
        "?" <>
        URI.encode_query(%{
          "version" => 1,
          "planning_run_id" => c.planning.run.contact_planning_run_id
        })

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
    assert [_, json] = Regex.run(~r/REQUIREMENT_CONTRIBUTION_INPUT=([^\n]+)/, output)
    Jason.decode!(json)
  end

  defp planning(context, offset \\ 0) do
    assert {:ok, result} =
             Planner.run(
               context.scope,
               context.mission.mission_id,
               context.requirement.contact_requirement_id,
               context.version.version,
               now: DateTime.add(@now, offset),
               list_routes: fn _, _, _ ->
                 {:ok, %{routes: [route(context.craft.spacecraft_id)], findings: []}}
               end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    assert [snapshot] = result.snapshots
    assert snapshot.eligible
    result
  end

  defp route(craft),
    do: %{
      route_key: "review-route",
      spacecraft_id: craft,
      provider_spacecraft_ref: "SC-review",
      source_endpoint_id: "source-review",
      routing_rule_id: "routing-review",
      link_assignment_id: "link-review",
      path_template_id: "path-review",
      path_template_version: 1,
      transport_id: "transport-review",
      transport_version: 1,
      provider_id: "provider-review",
      provider_version: 1,
      provider_account_id: "account-review",
      provider_account_version: 1,
      provider_account_grant_id: "grant-review",
      provider_account_grant_version: 1,
      provider_profile_id: "runtime-review",
      provider_profile_version: 1,
      service_profile_ref: %{"id" => "service-review", "version" => 1},
      delivery_profile_ref: %{"id" => "delivery-review", "version" => 1},
      delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
      provider_display_name: "Review Provider",
      service_display_name: "Downlink",
      delivery_display_name: "Primary",
      route_display_name: "Review route"
    }

  defp opportunity,
    do: %{
      "id" => "opportunity-review",
      "spacecraft_ref" => "SC-review",
      "ground_station_ref" => "station-review",
      "antenna_or_service_pool_ref" => "pool-review",
      "service_profile_ref" => "service-review",
      "starts_at" => iso(3600),
      "ends_at" => iso(4500),
      "expires_at" => iso(18_000),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "private_note" => "private-evidence-sentinel",
        "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
      }
    }

  defp iso(seconds), do: @now |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
