defmodule CadenceWeb.OpsPlanReviewPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlanApprovals, ContactPlans, ContactRequirements, Planner}
  alias Cadence.Control.Contacts
  alias CadenceWeb.TestFixtures

  @now ~U[2027-01-01 00:00:00Z]
  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/contact-plans/plan-review-check.mjs",
              __DIR__
            )

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
      Cadence.Spacecraft.new(%{
        spacecraft_id: Cadence.Ids.new("spacecraft"),
        mission_id: mission.mission_id,
        display_name: "Plan review craft"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, craft)

    {:ok, requirement, version} =
      ContactRequirements.create(scope, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id,
        service_direction: :downlink,
        contact_intent: "payload_downlink",
        earliest_start: DateTime.add(@now, 3600),
        latest_end: DateTime.add(@now, 28_800),
        success_measure: :minimum_duration,
        minimum_duration_seconds: 60,
        priority: :high,
        rationale: "Reviewed contact need"
      })

    {:ok, planning} =
      Planner.run(scope, mission.mission_id, requirement.contact_requirement_id, version.version,
        now: @now,
        list_routes: fn _, _, _ ->
          {:ok, %{routes: [route(craft.spacecraft_id)], findings: []}}
        end,
        search_opportunities: fn _, _, _, _, _ -> {:ok, %{opportunities: [opportunity()]}} end
      )

    {:ok, plan, plan_version} =
      ContactPlans.create(scope, mission.mission_id, %{
        planning_run_ids: [planning.run.contact_planning_run_id],
        selected_snapshot_ids: Enum.map(planning.snapshots, & &1.contact_opportunity_snapshot_id),
        rationale: String.duplicate("Reviewed plan ", 40)
      })

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      plan: plan,
      version: plan_version,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}"
    }
  end

  test "public native contribution submits, approves and executes with actual captured receipts",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "planning.plan-review"
    assert original["context"]["resourceId"] == c.plan.contact_plan_id
    assert original["data"]["actor_id"] == c.user.user_id

    for event <- ~w(submit-plan approve-plan execute-plan) do
      current = read(view, c.path, original)["snapshot"]
      [^event, input] = native(%{snapshot: current, action: event})
      assert input["payload"]["plan_evidence"]["content_sha256"] == c.version.content_sha256
      op = action(view, c.path, original, event, input)["snapshot"]
      assert op["status"] == "completed"
      result = op["receipt"]["result"]
      assert result["actor_id"] == c.user.user_id
      assert result["version"] == c.version.version
      assert result["contentSha256"] == c.version.content_sha256
      refreshed = read(view, c.path, original)["snapshot"]
      assert refreshed["data"]["operation"] == op

      assert [event, input] ==
               native(%{snapshot: current, action: event, operation: op, refreshed: refreshed})

      assert action(view, c.path, original, event, input)["snapshot"]["status"] == "rejected"
    end

    assert [approval] =
             ContactPlanApprovals.list(
               c.org.organization_id,
               c.mission.mission_id,
               c.plan.contact_plan_id
             )

    assert approval.decision == :approved

    assert [item] =
             Contacts.list_plan_execution(
               c.org.organization_id,
               c.mission.mission_id,
               c.plan.contact_plan_id,
               1
             )

    assert item.lifecycle_state == :failed
    assert item.last_error_document["code"] == "contact_plan_execution_route_not_ready"
    # This fixture has no real provider route. Governed execution records the
    # unavailable route without making a provider reservation request.
    assert page(view) == original
  end

  test "native rejection retains the actual decision and inserts no execution work", c do
    {:ok, _} =
      ContactPlans.submit(c.scope, c.mission.mission_id, c.plan.contact_plan_id, 1, "Submit")

    {:ok, view, _} = live(c.conn, c.path)
    current = page(view)
    [event, input] = native(%{snapshot: current, action: "reject-plan"})
    op = action(view, c.path, current, event, input)["snapshot"]
    assert op["status"] == "completed"
    refreshed = read(view, c.path, current)["snapshot"]

    assert [event, input] ==
             native(%{snapshot: current, action: event, operation: op, refreshed: refreshed})

    assert refreshed["data"]["detail"]["plan"]["reviewed_decision"]["decision"] == "rejected"

    assert Contacts.list_plan_execution(
             c.org.organization_id,
             c.mission.mission_id,
             c.plan.contact_plan_id,
             1
           ) == []
  end

  test "captured reads pin the initial version and preserve independent page selectors", c do
    {:ok, view, _} =
      live(c.conn, c.path <> "?opportunities_page=2&approvals_page=3&contact_plan_id=foreign")

    original = page(view)
    path = c.path <> "?opportunities_page=2&approvals_page=3&contact_plan_id=foreign"
    assert original["data"]["detail"]["plan"]["id"] == c.plan.contact_plan_id

    {:ok, _, newer} =
      ContactPlans.version(c.scope, c.mission.mission_id, c.plan.contact_plan_id, 1, %{
        rationale: "New proposal"
      })

    fresh = read(view, path, original)["snapshot"]
    d = fresh["data"]["detail"]
    assert d["plan"]["version"] == 1
    assert d["plan"]["current_version"] == newer.version
    assert d["query"]["opportunities_page"] == 2
    assert d["query"]["approvals_page"] == 3
    assert d["execution"]["entries"] == []

    op =
      action(view, path, original, "submit-plan", %{
        sequence: 1,
        payload: payload(c, "submission")
      })["snapshot"]

    assert op["status"] == "rejected"
    assert op["feedback"] == ["review_changed"]
  end

  test "path capture, sequence and mission authority reject substituted decisions", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    bad = put_in(payload(c, "submission"), ["plan_evidence", "plan_id"], "foreign")

    assert action(view, c.path, original, "submit-plan", %{sequence: 1, payload: bad})["snapshot"][
             "status"
           ] == "rejected"

    assert action(view, c.path, original, "submit-plan", %{
             sequence: 1,
             payload: payload(c, "submission")
           })["snapshot"]["status"] == "rejected"

    {:ok, %{lifecycle_state: :draft}, _} =
      ContactPlans.fetch(c.org.organization_id, c.mission.mission_id, c.plan.contact_plan_id)

    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, c.org)

    {:ok, _} =
      ContactPlans.submit(c.scope, c.mission.mission_id, c.plan.contact_plan_id, 1, "Submit")

    {:ok, denied, _} = live(TestFixtures.member_conn(member), c.path)
    p = page(denied)
    refute p["data"]["detail"]["permissions"]["decide"]

    op =
      action(denied, c.path, p, "approve-plan", %{sequence: 1, payload: payload(c, "decision")})[
        "snapshot"
      ]

    assert op["status"] == "rejected"
    assert op["feedback"] == ["forbidden"]

    assert ContactPlanApprovals.list(
             c.org.organization_id,
             c.mission.mission_id,
             c.plan.contact_plan_id
           ) == []
  end

  test "captured tokens expire on departure and revoked sessions cannot recover reads", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"],
      "version" => 2
    })

    assert_reply(view, %{ok: false})

    render_hook(view, "host:context", %{
      "path" => "/missions/#{c.mission.mission_id}/ops/requirements"
    })

    assert_reply(view, %{ok: true})
    assert read(view, c.path, original)["ok"] == false
    render_hook(view, "host:context", %{"path" => c.path})
    assert_reply(view, %{ok: true})
    fresh = page(view)
    refute fresh["token"] == original["token"]
    :ok = Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => fresh["id"],
      "token" => fresh["token"]
    })

    assert_redirect(view, "/sign-in")
  end

  test "native reason bounds admit UTF8 text beyond the generic request boundary", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    reason = String.duplicate("界", 200)
    input = put_in(payload(c, "submission"), ["submission", "reason"], reason)
    op = action(view, c.path, original, "submit-plan", %{sequence: 1, payload: input})["snapshot"]
    assert op["status"] == "completed"
    assert op["input"]["submission"]["reason"] == reason
    fresh = read(view, c.path, original)["snapshot"]
    assert fresh["status"] == "ready"
    assert fresh["data"]["operation"] == op
  end

  defp payload(c, wrapper) do
    input = %{
      "contact_plan_id" => c.plan.contact_plan_id,
      "plan_evidence" => %{
        "contract_version" => 1,
        "organization_id" => c.org.organization_id,
        "mission_id" => c.mission.mission_id,
        "plan_id" => c.plan.contact_plan_id,
        "plan_version" => c.version.version,
        "content_sha256" => c.version.content_sha256
      }
    }

    Map.put(input, wrapper, %{"reason" => "Reviewed actual producer evidence"})
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, p) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action(view, path, p, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
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
    assert [_, json] = Regex.run(~r/PLAN_CONTRIBUTION_INPUT=([^\n]+)/, output)
    Jason.decode!(json)
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
        "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
      }
    }

  defp iso(seconds), do: @now |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
