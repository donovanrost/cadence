defmodule CadenceWeb.Console.TemplateSupersessionTest do
  @moduledoc "CP3 review (domain, 2026-11-09): supersession keeps planned work and runs after v2 materializes."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningStarts,
    PlanSupersession,
    TemplateSupersession
  }

  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

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

    %{org: org, user: user, membership: membership, mission: mission, scope: scope}
  end

  defp attrs(target, anchor) do
    %{
      name: "Recurring downlink",
      target_document: target,
      schedule_document: %{
        "type" => "fixed_interval",
        "anchor_at" => DateTime.to_iso8601(anchor),
        "interval_seconds" => 21_600,
        "window_offset_seconds" => 0,
        "window_duration_seconds" => 21_600
      },
      requirement_document: %{
        "service_direction" => "downlink",
        "contact_intent" => "recurring_payload_downlink",
        "success_measure" => "minimum_duration",
        "minimum_duration_seconds" => 60,
        "preferred_duration_seconds" => 60,
        "minimum_data_volume_bytes" => nil,
        "contact_count" => 1,
        "minimum_separation_seconds" => 0,
        "priority" => "routine",
        "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
        "station_constraints_document" => %{"allowed" => [], "excluded" => []},
        "policy_constraints_document" => %{},
        "approval_policy_document" => %{"mode" => "manual"},
        "rationale" => "Supersession test",
        "metadata" => %{}
      },
      catch_up_policy_document: %{
        "maximum_occurrences_per_run" => 8,
        "maximum_lookback_seconds" => 86_400
      }
    }
  end

  test "a requirement taken up by a submitted plan is kept; a draft's is superseded", c do
    for {template_id, submit?} <- [{"tmpl-kept", true}, {"tmpl-gone", false}] do
      fixture =
        ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission,
          metadata: %{
            "generation" => %{
              "kind" => "contact_requirement_template",
              "contact_requirement_template_id" => template_id,
              "contact_requirement_template_version" => 1,
              "occurrence_at" => "2027-01-01T01:00:00Z"
            }
          }
        )

      target = %{"kind" => "spacecraft_ids", "spacecraft_ids" => [fixture.craft.spacecraft_id]}

      {:ok, _template, _v1} =
        ContactRequirementTemplates.create(
          c.scope,
          c.mission.mission_id,
          Map.put(
            attrs(target, ContactPlanningFixtures.now()),
            :contact_requirement_template_id,
            template_id
          )
        )

      # Submitted before the template changes: the plan took the requirement up.
      if submit? do
        {:ok, _} =
          ContactPlans.submit(
            c.scope,
            c.mission.mission_id,
            fixture.plan.contact_plan_id,
            1,
            "Review"
          )
      end

      {:ok, _template, v2} =
        ContactRequirementTemplates.version(c.scope, c.mission.mission_id, template_id, 1, %{
          name: "v2"
        })

      if submit? do
        # The bulk fleet path also rechecks plan uptake after preparing candidates.
        now = DateTime.utc_now()

        prepared =
          TemplateSupersession.prepare(
            c.org.organization_id,
            c.mission.mission_id,
            [
              %{
                version: v2,
                spacecraft_ids: [fixture.craft.spacecraft_id],
                occurrences: [~U[2027-01-01 01:00:00Z]]
              }
            ],
            now
          )

        id = fixture.requirement.contact_requirement_id
        assert [{^v2, [{^id, 1, :template_versioned}]}] = prepared

        assert {:ok, :ok} =
                 Cadence.Repo.transaction(fn ->
                   TemplateSupersession.cancel_prepared(
                     c.scope,
                     c.mission.mission_id,
                     prepared,
                     now
                   )
                 end)
      end

      result =
        TemplateSupersession.supersede(
          c.scope,
          v2,
          [fixture.craft.spacecraft_id],
          DateTime.utc_now(),
          {~U[2027-01-01 00:00:00Z], ~U[2027-01-02 00:00:00Z]}
        )

      {:ok, requirement, _} =
        ContactRequirements.fetch(
          c.org.organization_id,
          c.mission.mission_id,
          fixture.requirement.contact_requirement_id
        )

      if submit? do
        assert result == %{superseded: 0}
        assert requirement.lifecycle_state == :active
      else
        assert result == %{superseded: 1}
        assert requirement.lifecycle_state == :canceled
        assert requirement.lifecycle_reason =~ "template_versioned"
      end
    end
  end

  test "bumping a template supersedes the draft on read at once, and submit refuses it (U27)",
       c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission,
        metadata: %{
          "generation" => %{
            "kind" => "contact_requirement_template",
            "contact_requirement_template_id" => "tmpl-u27",
            "contact_requirement_template_version" => 1
          }
        }
      )

    target = %{"kind" => "spacecraft_ids", "spacecraft_ids" => [fixture.craft.spacecraft_id]}

    {:ok, _, _} =
      ContactRequirementTemplates.create(
        c.scope,
        c.mission.mission_id,
        Map.put(
          attrs(target, ContactPlanningFixtures.now()),
          :contact_requirement_template_id,
          "tmpl-u27"
        )
      )

    path =
      "/api/v1/missions/#{c.mission.mission_id}/contact-plans/#{fixture.plan.contact_plan_id}"

    read = fn ->
      c.user
      |> TestFixtures.member_conn()
      |> get(path)
      |> json_response(200)
      |> Map.fetch!("data")
    end

    assert read.()["superseded"] == nil

    {:ok, _, _} =
      ContactRequirementTemplates.version(c.scope, c.mission.mission_id, "tmpl-u27", 1, %{
        name: "v2"
      })

    assert %{
             "state" => "superseded",
             "superseded" => %{
               "reason" => "template_changed",
               "changes" => [
                 %{
                   "kind" => "template",
                   "id" => "tmpl-u27",
                   "from_version" => 1,
                   "to_version" => 2
                 }
               ]
             }
           } = read.()

    conn =
      c.user
      |> TestFixtures.member_conn()
      |> post(path <> "/submit", %{"expected_version" => 1, "operation_id" => "op-u27"})

    assert %{
             "code" => "plan_superseded",
             "details" => %{"superseded" => %{"reason" => "template_changed"}}
           } =
             json_response(conn, 409)["error"]
  end

  test "a draft sharing a requirement that a submitted plan keeps isn't superseded (repairs)",
       c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission,
        metadata: %{
          "generation" => %{
            "contact_requirement_template_id" => "tmpl-kept-by-plan",
            "contact_requirement_template_version" => 1
          }
        }
      )

    target = %{"kind" => "spacecraft_ids", "spacecraft_ids" => [fixture.craft.spacecraft_id]}

    {:ok, _, _} =
      ContactRequirementTemplates.create(
        c.scope,
        c.mission.mission_id,
        Map.put(
          attrs(target, ContactPlanningFixtures.now()),
          :contact_requirement_template_id,
          "tmpl-kept-by-plan"
        )
      )

    {:ok, _} =
      ContactPlans.submit(
        c.scope,
        c.mission.mission_id,
        fixture.plan.contact_plan_id,
        1,
        "Book it"
      )

    {:ok, repair, repair_version} =
      ContactPlans.create(c.scope, c.mission.mission_id, %{
        planning_run_ids: [fixture.planning.run.contact_planning_run_id],
        selected_snapshot_ids:
          Enum.map(fixture.planning.snapshots, & &1.contact_opportunity_snapshot_id),
        rationale: "Repair proposal"
      })

    {:ok, _, _} =
      ContactRequirementTemplates.version(
        c.scope,
        c.mission.mission_id,
        "tmpl-kept-by-plan",
        1,
        %{name: "v2"}
      )

    assert PlanSupersession.check(
             c.org.organization_id,
             c.mission.mission_id,
             repair,
             repair_version
           ) == nil
  end

  test "a failed v2 materialization in a fleet start rolls the cancels back (review 4)", c do
    ContactPlanningFixtures.active_policy!(c.scope, c.mission.mission_id)
    craft = TestFixtures.persist_spacecraft!(c.mission)
    target = %{"kind" => "spacecraft_ids", "spacecraft_ids" => [craft.spacecraft_id]}
    day = ~U[2027-03-02 00:00:00Z]
    until = DateTime.add(day, 86_400)

    {:ok, template, _} =
      ContactRequirementTemplates.create(c.scope, c.mission.mission_id, attrs(target, day))

    id = template.contact_requirement_template_id

    {:ok, v1_rows} =
      ContactRequirementTemplates.materialize(
        c.scope,
        c.mission.mission_id,
        id,
        day,
        DateTime.add(until, -1)
      )

    {:ok, _, _} =
      ContactRequirementTemplates.version(c.scope, c.mission.mission_id, id, 1, %{name: "v2"})

    fleet_run = %{
      "horizon_start" => DateTime.to_iso8601(day),
      "horizon_end" => DateTime.to_iso8601(until),
      "include_recurring" => true
    }

    # Another day's start claims the operation id first.
    other_day = %{
      "horizon_start" => DateTime.to_iso8601(DateTime.add(day, 2 * 86_400)),
      "horizon_end" => DateTime.to_iso8601(DateTime.add(day, 3 * 86_400)),
      "include_recurring" => true
    }

    {:ok, other} =
      FleetPlanningStarts.preview(c.scope, c.mission.mission_id, %{"fleet_run" => other_day})

    {:ok, _run, _refs} =
      FleetPlanningStarts.create(
        c.scope,
        c.mission.mission_id,
        %{"fleet_run" => other_day, "evidence" => other.evidence},
        operation_id: "op-dup"
      )

    {:ok, review} =
      FleetPlanningStarts.preview(c.scope, c.mission.mission_id, %{"fleet_run" => fleet_run})

    # This start materializes v2 and supersedes v1, then fails recording the operation id, so
    # the whole claim (including the cancels) rolls back.
    assert {:error, _reason} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission.mission_id,
               %{"fleet_run" => fleet_run, "evidence" => review.evidence},
               operation_id: "op-dup"
             )

    for row <- v1_rows do
      {:ok, requirement, _} =
        ContactRequirements.fetch(
          c.org.organization_id,
          c.mission.mission_id,
          row.requirement.contact_requirement_id
        )

      assert requirement.lifecycle_state == :active
    end
  end

  test "the dry run lists the open drafts a template or requirement save would supersede", c do
    fixture =
      ContactPlanningFixtures.plan_fixture(c.org, c.user, c.membership, c.mission,
        metadata: %{
          "generation" => %{
            "contact_requirement_template_id" => "tmpl-dry",
            "contact_requirement_template_version" => 1
          }
        }
      )

    base = "/api/v1/missions/#{c.mission.mission_id}/contact-planning"

    read = fn path ->
      c.user |> TestFixtures.member_conn() |> get(base <> path) |> json_response(200)
    end

    plan_id = fixture.plan.contact_plan_id

    assert %{"data" => %{"drafts" => [draft], "decided" => decided}} =
             read.("/templates/tmpl-dry/supersedes")

    # U48: nothing kept or closed yet (the draft-only day is superseded, not kept).
    assert decided == %{"planned_or_started" => [], "closed" => [], "canceled" => []}

    assert %{
             "plan" => %{"id" => ^plan_id, "version" => 1},
             "state" => "draft",
             "day" => "2027-01-01"
           } =
             draft

    assert %{"name" => _} = draft["author"]

    requirement_id = fixture.requirement.contact_requirement_id
    assert %{"data" => %{"drafts" => [_]}} = read.("/requirements/#{requirement_id}/supersedes")
    assert %{"data" => %{"drafts" => []}} = read.("/templates/other/supersedes")

    {:ok, _} = ContactPlans.submit(c.scope, c.mission.mission_id, plan_id, 1, "Book")
    assert %{"data" => %{"drafts" => []}} = read.("/templates/tmpl-dry/supersedes")
  end

  test "a fleet start leaves v1's requirements out of review and supersedes them after v2 materializes",
       c do
    ContactPlanningFixtures.active_policy!(c.scope, c.mission.mission_id)
    craft = TestFixtures.persist_spacecraft!(c.mission)
    target = %{"kind" => "spacecraft_ids", "spacecraft_ids" => [craft.spacecraft_id]}
    day = ~U[2027-03-01 00:00:00Z]
    until = DateTime.add(day, 86_400)

    {:ok, template, _} =
      ContactRequirementTemplates.create(c.scope, c.mission.mission_id, attrs(target, day))

    id = template.contact_requirement_template_id

    {:ok, v1_rows} =
      ContactRequirementTemplates.materialize(
        c.scope,
        c.mission.mission_id,
        id,
        day,
        DateTime.add(until, -1)
      )

    v1_ids = MapSet.new(v1_rows, & &1.requirement.contact_requirement_id)

    {:ok, _, _} =
      ContactRequirementTemplates.version(c.scope, c.mission.mission_id, id, 1, %{name: "v2"})

    fleet_run = %{
      "horizon_start" => DateTime.to_iso8601(day),
      "horizon_end" => DateTime.to_iso8601(until),
      "include_recurring" => true
    }

    {:ok, review} =
      FleetPlanningStarts.preview(c.scope, c.mission.mission_id, %{"fleet_run" => fleet_run})

    reviewed = Enum.map(review.requirements.entries, & &1.id)
    assert Enum.all?(reviewed, &(not MapSet.member?(v1_ids, &1)))

    {:ok, _run, refs} =
      FleetPlanningStarts.create(c.scope, c.mission.mission_id, %{
        "fleet_run" => fleet_run,
        "evidence" => review.evidence
      })

    ref_ids = MapSet.new(refs, & &1.contact_requirement_id)
    # v2's four occurrences were generated and reviewed into the run instead.
    assert MapSet.size(ref_ids) == 4

    assert MapSet.disjoint?(ref_ids, v1_ids)

    for id <- v1_ids do
      {:ok, requirement, _} =
        ContactRequirements.fetch(c.org.organization_id, c.mission.mission_id, id)

      assert requirement.lifecycle_state == :canceled
    end
  end
end
