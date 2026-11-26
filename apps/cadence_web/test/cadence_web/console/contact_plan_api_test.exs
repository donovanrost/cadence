defmodule CadenceWeb.Console.ContactPlanAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates}
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    %{
      org: org,
      user: user,
      membership: membership,
      mission: mission,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_json(c, path), do: c.user |> TestFixtures.member_conn() |> get(c.base <> path)

  test "an empty mission has no plans; an unknown plan is not found", c do
    assert json_response(get_json(c, "/contact-plans"), 200)["data"] == %{
             "plans" => [],
             "repair_proposals" => []
           }

    assert json_response(get_json(c, "/contact-plans/nope"), 404)["error"]["code"] ==
             "plan_not_found"

    assert json_response(get_json(c, "/contact-plans?day=bad"), 422)["error"]["details"]["day"]

    assert json_response(get_json(c, "/contact-plans?state=bad"), 422)["error"]["details"][
             "state"
           ]

    # Drift sweep: the derived states filter too (none here).
    for state <- ~w(interrupted unconfirmed) do
      assert %{"plans" => [], "repair_proposals" => []} =
               json_response(get_json(c, "/contact-plans?state=#{state}"), 200)["data"]
    end
  end

  test "lists the plan and shows passes, demand, unmet and conflicts", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    plan_id = fixture.plan.contact_plan_id

    [row] =
      json_response(get_json(c, "/contact-plans?day=2027-01-01&state=draft"), 200)["data"][
        "plans"
      ]

    assert %{"id" => ^plan_id, "version" => 1, "state" => "draft"} = row
    assert %{"passes" => 1, "conflicts" => 0, "unsatisfied" => 0, "minutes" => 15} = row["counts"]
    assert row["ready_to_approve"] == true

    assert json_response(get_json(c, "/contact-plans?day=2027-01-02"), 200)["data"]["plans"] == []

    detail = json_response(get_json(c, "/contact-plans/#{plan_id}"), 200)["data"]

    assert [%{"spacecraft_id" => sc, "station" => station, "synthetic" => true}] =
             detail["passes"]

    # No Cadence station is named "station-review" in this fixture.
    assert station == %{"ref" => "station-review", "id" => nil, "code" => nil, "name" => nil}

    assert sc == fixture.craft.spacecraft_id
    assert detail["repair_of"] == nil
    # qa #30: a plan with no applied repairs is its own chain and head.
    assert %{"chain" => [%{"id" => ^plan_id}], "chain_head" => ^plan_id} = detail
    # A draft hasn't executed: no execution summary yet.
    assert detail["execution"] == nil
    # ...and no pass has a booking yet (K1 8e).
    assert [%{"booking" => nil}] = detail["passes"]
    assert is_binary(detail["created_at"]) and is_binary(detail["version_created_at"])
    assert %{"kind" => "user", "name" => name} = detail["author"]
    assert name == c.user.display_name
    assert detail["unmet"] == []
    assert detail["conflicts"] == []

    assert %{"rule_met" => 1, "rule_total" => 1, "spacecraft" => [demand], "rules" => [rule]} =
             detail["demand"]

    assert %{
             "spacecraft_id" => ^sc,
             "rule_met" => true,
             "contacts" => %{"have" => 1, "need" => 1}
           } = demand

    assert rule["text"] =~ "at least 1 min"

    # K1 C panel (lead): the pass is 01:00-01:15Z, so the day's longest gap is 01:15Z to 24:00Z
    # (the edges count). No rule carries a limit or an uplink count yet.
    assert demand["longest_gap"] == %{
             "seconds" => 81_900,
             "limit_seconds" => nil,
             "from" => "2027-01-01T01:15:00Z",
             "to" => "2027-01-02T00:00:00Z"
           }

    assert demand["uplink_passes"] == %{"have" => 0, "need" => nil}

    # K1's offer clock: a draft has sent nothing, so its one pass's expiry sets it.
    [%{"snapshot_id" => snapshot_id, "expires_at" => expires_at}] = detail["passes"]
    assert instant(expires_at) == ~U[2027-01-01 05:00:00Z]

    assert %{
             "at" => freeze_at,
             "snapshot_id" => ^snapshot_id,
             "provider" => %{"id" => "provider-review"},
             "by_provider" => [%{"provider" => %{"id" => "provider-review"}, "at" => _}]
           } = detail["provider_freeze"]

    assert instant(freeze_at) == ~U[2027-01-01 05:00:00Z]
  end

  defp instant(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.truncate(at, :second)
  end

  test "setup says what is missing before drafting, and demand counts the day", c do
    setup = json_response(get_json(c, "/contact-plans/setup"), 200)["data"]["setup"]

    assert %{
             "ready" => false,
             "missing" => ["fleet_planning_policy", "contact_requirements"],
             "policy" => nil
           } =
             setup

    scope =
      Scope.new(%{
        user: c.user,
        organization_id: c.org.organization_id,
        organization_membership: c.membership
      })

    policy = ContactPlanningFixtures.active_policy!(scope, c.mission.mission_id)
    ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    TestFixtures.persist_spacecraft!(c.mission, display_name: "No rule craft")

    setup = json_response(get_json(c, "/contact-plans/setup"), 200)["data"]["setup"]
    assert %{"ready" => true, "missing" => [], "requirements" => 1, "templates" => 0} = setup
    assert setup["policy"]["id"] == policy.fleet_planning_policy_id

    demand = json_response(get_json(c, "/contact-plans/demand?day=2027-01-01"), 200)["data"]

    assert %{
             "spacecraft_with_rules" => 1,
             "contacts_needed" => 1,
             "without_rule" => 1,
             "spacecraft_total" => 2
           } =
             demand

    assert json_response(get_json(c, "/contact-plans/demand?day=2027-01-05"), 200)["data"][
             "contacts_needed"
           ] == 0

    assert json_response(get_json(c, "/contact-plans/demand"), 422)["error"]["details"]["day"]
  end

  test "demand counts a template occurrence once, before and after it materializes", c do
    scope =
      Scope.new(%{
        user: c.user,
        organization_id: c.org.organization_id,
        organization_membership: c.membership
      })

    craft = TestFixtures.persist_spacecraft!(c.mission)

    {:ok, template, _version} =
      ContactRequirementTemplates.create(scope, c.mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id,
        schedule_document: %{
          "type" => "fixed_interval",
          "anchor_at" => "2027-01-01T00:00:00Z",
          "interval_seconds" => 21_600,
          "window_offset_seconds" => 0,
          "window_duration_seconds" => 21_600
        },
        requirement_document: %{
          "service_direction" => "downlink",
          "contact_intent" => "recurring_payload_downlink",
          "success_measure" => "minimum_duration",
          "minimum_duration_seconds" => 300,
          "preferred_duration_seconds" => 300,
          "minimum_data_volume_bytes" => nil,
          "contact_count" => 1,
          "minimum_separation_seconds" => 0,
          "priority" => "routine",
          "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
          "station_constraints_document" => %{"allowed" => [], "excluded" => []},
          "policy_constraints_document" => %{},
          "approval_policy_document" => %{"mode" => "manual"},
          "rationale" => "Demand test",
          "metadata" => %{}
        },
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 8,
          "maximum_lookback_seconds" => 86_400
        }
      })

    needed = fn ->
      json_response(get_json(c, "/contact-plans/demand?day=2027-01-03"), 200)["data"][
        "contacts_needed"
      ]
    end

    assert needed.() == 4

    {:ok, materialized} =
      ContactRequirementTemplates.materialize(
        scope,
        c.mission.mission_id,
        template.contact_requirement_template_id,
        ~U[2027-01-03 00:00:00Z],
        ~U[2027-01-03 23:00:00Z]
      )

    assert length(materialized) == 4

    assert needed.() == 4
  end

  test "a draft overtaken by a newer requirement version reads as superseded, with why", c do
    fixture = ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission)
    plan_id = fixture.plan.contact_plan_id

    detail = json_response(get_json(c, "/contact-plans/#{plan_id}"), 200)["data"]
    assert %{"state" => "draft", "superseded" => nil} = detail

    scope =
      Scope.new(%{
        user: c.user,
        organization_id: c.org.organization_id,
        organization_membership: c.membership
      })

    requirement_id = fixture.requirement.contact_requirement_id

    {:ok, _, _} =
      ContactRequirements.version(
        scope,
        c.mission.mission_id,
        requirement_id,
        1,
        %{priority: :critical}
      )

    detail = json_response(get_json(c, "/contact-plans/#{plan_id}"), 200)["data"]
    assert detail["state"] == "superseded"
    assert detail["ready_to_approve"] == false

    assert %{
             "reason" => "requirement_changed",
             "by" => %{"name" => _},
             "changes" => [
               %{
                 "kind" => "requirement",
                 "id" => ^requirement_id,
                 "from_version" => 1,
                 "to_version" => 2
               }
             ]
           } = detail["superseded"]

    [row] = json_response(get_json(c, "/contact-plans?day=2027-01-01"), 200)["data"]["plans"]
    assert %{"state" => "superseded", "superseded" => %{"reason" => "requirement_changed"}} = row
  end

  test "alternatives show the effect of adding a pass; versions add and remove passes", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission, select?: false)

    plan_id = fixture.plan.contact_plan_id
    sc = fixture.craft.spacecraft_id

    alternatives =
      json_response(
        get_json(c, "/contact-plans/#{plan_id}/alternatives?spacecraft_id=#{sc}"),
        200
      )[
        "data"
      ]

    assert %{
             "rule_met" => false,
             "contacts" => %{"have" => 0, "need" => 1},
             "alternatives" => [alternative]
           } = alternatives

    assert %{
             "rule_met_after" => true,
             "contacts_after" => %{"have" => 1, "need" => 1},
             "clashes_with" => [],
             # The whole day without a pass; with it, 01:15Z to 24:00Z.
             "longest_gap_after_seconds" => 81_900
           } =
             alternative["effect"]

    assert %{"seconds" => 86_400, "from" => "2027-01-01T00:00:00Z"} = alternatives["longest_gap"]

    post_edit = fn body ->
      c.user
      |> TestFixtures.member_conn()
      |> post(c.base <> "/contact-plans/#{plan_id}/versions", body)
    end

    added =
      json_response(
        post_edit.(%{"expected_version" => 1, "add" => [alternative["snapshot_id"]]}),
        200
      )[
        "data"
      ]

    assert %{"version" => 2, "unmet" => [], "ready_to_approve" => true} = added
    assert [%{"snapshot_id" => _}] = added["passes"]

    assert json_response(post_edit.(%{"expected_version" => 1, "remove" => []}), 409)["error"][
             "code"
           ] ==
             "plan_changed"

    removed =
      json_response(
        post_edit.(%{"expected_version" => 2, "remove" => [alternative["snapshot_id"]]}),
        200
      )[
        "data"
      ]

    assert %{"version" => 3, "passes" => []} = removed

    assert json_response(get_json(c, "/contact-plans/#{plan_id}/alternatives"), 422)["error"][
             "details"
           ][
             "spacecraft_id"
           ]
  end

  test "a plan without its pass lists the requirement as unmet", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission, select?: false)

    detail =
      json_response(get_json(c, "/contact-plans/#{fixture.plan.contact_plan_id}"), 200)["data"]

    assert [%{"requirement_id" => req, "spacecraft_id" => sc, "why" => [_ | _]}] = detail["unmet"]
    assert req == fixture.requirement.contact_requirement_id
    assert sc == fixture.craft.spacecraft_id
    assert detail["ready_to_approve"] == false
    assert detail["demand"]["rule_met"] == 0

    assert detail["demand"]["coverage"] == %{
             "spacecraft_uncovered" => 1,
             "contacts_short" => 1,
             "gaps" => 1
           }
  end
end
