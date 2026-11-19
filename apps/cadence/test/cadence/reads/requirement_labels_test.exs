defmodule Cadence.Reads.RequirementLabelsTest do
  @moduledoc "U73/U74: a requirement's name for people, and a pass's 'Booked' row words."
  use Cadence.DataCase, async: false

  alias Cadence.ContactPlanExecutionFixtures, as: Plan
  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates}
  alias Cadence.Reads.{PassBooking, RequirementLabels}

  test "a plain requirement is named by its rule; a pass booked from the plan gets its day" do
    c = Plan.setup_plan()

    [{requirement, version}] = ContactRequirements.list(c.organization_id, c.mission_id)
    ref = {requirement.contact_requirement_id, version.version}

    assert %{^ref => %{name: name, spacecraft: spacecraft}} =
             RequirementLabels.load(c.organization_id, c.mission_id, [ref])

    # U73: the version's window, to tell several gaps of one requirement apart.
    assert %{^ref => %{window: %{from: from, to: to}}} =
             RequirementLabels.load(c.organization_id, c.mission_id, [ref])

    assert from == version.earliest_start and to == version.latest_end

    assert name =~ ~r/^\d+ \w+ contacts?/
    assert %{id: id, name: craft} = spacecraft
    assert id == version.spacecraft_id and is_binary(craft)

    # The current version when none is given.
    current = {requirement.contact_requirement_id, nil}

    assert %{^current => %{name: ^name}} =
             RequirementLabels.load(c.organization_id, c.mission_id, [current])

    pass = %{
      plan: %{id: c.plan.contact_plan_id, version: c.plan.current_version},
      requirement: %{id: requirement.contact_requirement_id, version: version.version}
    }

    assert %{plan: %{day: %Date{}}, requirement: %{name: ^name}} =
             PassBooking.names(c.organization_id, c.mission_id, pass)

    assert %{plan: nil, requirement: nil} =
             PassBooking.names(c.organization_id, c.mission_id, %{plan: nil, requirement: nil})

    assert RequirementLabels.load(c.organization_id, c.mission_id, [{"nope", 1}]) == %{}
  end

  test "a requirement a template generated is named by its template" do
    c = Plan.setup_plan()
    [{_requirement, plain}] = ContactRequirements.list(c.organization_id, c.mission_id)
    now = Plan.now()

    assert {:ok, template, _version} =
             ContactRequirementTemplates.create(
               c.admin_scope,
               c.mission_id,
               %{
                 name: "Block 1 daily",
                 spacecraft_id: plain.spacecraft_id,
                 schedule_document: %{
                   "type" => "fixed_interval",
                   "anchor_at" => DateTime.to_iso8601(now),
                   "interval_seconds" => 3_600,
                   "window_offset_seconds" => 600,
                   "window_duration_seconds" => 1_800
                 },
                 requirement_document: %{
                   "service_direction" => "downlink",
                   "contact_intent" => "recurring_payload_downlink",
                   "success_measure" => "minimum_duration",
                   "minimum_duration_seconds" => 600,
                   "preferred_duration_seconds" => 900,
                   "minimum_data_volume_bytes" => nil,
                   "contact_count" => 1,
                   "minimum_separation_seconds" => 0,
                   "priority" => "high",
                   "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
                   "station_constraints_document" => %{"allowed" => [], "excluded" => []},
                   "policy_constraints_document" => %{},
                   "approval_policy_document" => %{"mode" => "manual"},
                   "rationale" => "Daily payload downlink",
                   "metadata" => %{}
                 },
                 catch_up_policy_document: %{
                   "maximum_occurrences_per_run" => 10,
                   "maximum_lookback_seconds" => 86_400
                 }
               },
               now: now
             )

    assert {:ok, [first | _]} =
             ContactRequirementTemplates.materialize(
               c.admin_scope,
               c.mission_id,
               template.contact_requirement_template_id,
               now,
               DateTime.add(now, 3_600),
               now: now
             )

    ref = {first.requirement.contact_requirement_id, first.requirement_version.version}

    assert %{^ref => %{name: "Block 1 daily"}} =
             RequirementLabels.load(c.organization_id, c.mission_id, [ref])
  end
end
