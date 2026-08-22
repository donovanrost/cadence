defmodule Cadence.ContactPlanning.ContactRequirementTemplatesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    RequirementSchedule
  }

  alias Cadence.Spacecraft

  @organization_id "org-requirement-templates"
  @mission_id "mission-requirement-templates"
  @spacecraft_id "spacecraft-requirement-templates"
  @now ~U[2026-07-17 00:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: mission.mission_id,
        display_name: "Aurora Template"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    %{
      admin_scope: scope(organization, :organization_admin),
      member_scope: scope(organization, :member)
    }
  end

  test "an organization administrator creates and immutably versions a template", context do
    assert {:ok, template, version_one} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               template_attrs(),
               now: @now
             )

    assert template.lifecycle_state == :active
    assert template.current_version == 1
    assert version_one.spacecraft_id == @spacecraft_id
    assert version_one.schedule_document["type"] == "fixed_interval"
    assert version_one.schedule_document["interval_seconds"] == 3_600
    assert version_one.content_sha256 =~ ~r/\A[0-9a-f]{64}\z/

    assert {:ok, template_two, version_two} =
             ContactRequirementTemplates.version(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               1,
               %{
                 "requirement_document" => requirement_document(%{"priority" => "critical"})
               },
               now: DateTime.add(@now, 60, :second)
             )

    assert template_two.current_version == 2
    assert version_two.version == 2
    assert version_two.requirement_document["priority"] == "critical"
    assert version_two.schedule_document == version_one.schedule_document
    refute version_two.content_sha256 == version_one.content_sha256

    assert [^version_two, ^version_one] =
             ContactRequirementTemplates.list_versions(
               @organization_id,
               @mission_id,
               template.contact_requirement_template_id
             )

    assert {:error, :stale_contact_requirement_template_version} =
             ContactRequirementTemplates.version(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               1,
               %{requirement_document: requirement_document()}
             )
  end

  test "members cannot manage templates and invalid schedules fail before persistence", context do
    assert {:error, :forbidden} =
             ContactRequirementTemplates.create(
               context.member_scope,
               @mission_id,
               template_attrs()
             )

    assert {:error, {:invalid_contact_requirement_template, message}} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               template_attrs(%{
                 schedule_document: %{
                   "type" => "fixed_interval",
                   "anchor_at" => DateTime.to_iso8601(@now),
                   "interval_seconds" => 0,
                   "window_duration_seconds" => 1_800
                 }
               })
             )

    assert message =~ "interval_seconds"

    assert {:error, :contact_requirement_template_spacecraft_not_found} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               template_attrs(%{spacecraft_id: "spacecraft-outside"})
             )
  end

  test "materialization creates ordinary Requirements exactly once with provenance", context do
    assert {:ok, template, _version} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               template_attrs(),
               now: @now
             )

    horizon_end = DateTime.add(@now, 7_200, :second)

    assert {:ok, results} =
             ContactRequirementTemplates.materialize(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               @now,
               horizon_end,
               now: @now
             )

    assert length(results) == 3
    assert Enum.all?(results, &(&1.status == :created))

    first = hd(results)
    assert first.occurrence.generation_state == :generated
    assert first.requirement.current_version == 1
    assert first.requirement_version.earliest_start == DateTime.add(@now, 600, :second)
    assert first.requirement_version.latest_end == DateTime.add(@now, 2_400, :second)

    assert first.requirement_version.metadata["generation"] == %{
             "kind" => "contact_requirement_template",
             "contact_requirement_template_id" => template.contact_requirement_template_id,
             "contact_requirement_template_version" => 1,
             "occurrence_at" => DateTime.to_iso8601(@now)
           }

    assert {:ok, repeated} =
             ContactRequirementTemplates.materialize(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               @now,
               horizon_end,
               now: DateTime.add(@now, 30, :second)
             )

    assert length(repeated) == 3
    assert Enum.all?(repeated, &(&1.status == :existing))

    occurrences =
      ContactRequirementTemplates.list_occurrences(
        @organization_id,
        @mission_id,
        template.contact_requirement_template_id
      )

    assert length(occurrences) == 3
    assert length(ContactRequirements.list(@organization_id, @mission_id)) == 3
  end

  test "concurrent materialization converges on one occurrence and Requirement", context do
    attrs =
      template_attrs(%{
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 1,
          "maximum_lookback_seconds" => 86_400
        }
      })

    assert {:ok, template, _version} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               attrs,
               now: @now
             )

    results =
      1..2
      |> Task.async_stream(
        fn _attempt ->
          ContactRequirementTemplates.materialize(
            context.admin_scope,
            @mission_id,
            template.contact_requirement_template_id,
            @now,
            @now,
            now: @now
          )
        end,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, [_result]}, &1))

    statuses =
      Enum.map(results, fn {:ok, [result]} -> result.status end)

    assert Enum.sort(statuses) == [:created, :existing]

    assert [_occurrence] =
             ContactRequirementTemplates.list_occurrences(
               @organization_id,
               @mission_id,
               template.contact_requirement_template_id
             )

    assert [_requirement] = ContactRequirements.list(@organization_id, @mission_id)
  end

  test "pause, activation, close, and bounded catch-up are explicit", context do
    attrs =
      template_attrs(%{
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 2,
          "maximum_lookback_seconds" => 3_600
        }
      })

    assert {:ok, template, _version} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               attrs,
               now: @now
             )

    assert {:ok, paused} =
             ContactRequirementTemplates.pause(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               1,
               "Hold during commissioning"
             )

    assert paused.lifecycle_state == :paused

    assert {:error, :contact_requirement_template_not_active} =
             ContactRequirementTemplates.materialize(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               @now,
               DateTime.add(@now, 10_800, :second)
             )

    assert {:ok, active} =
             ContactRequirementTemplates.activate(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               1,
               "Commissioning complete"
             )

    assert active.lifecycle_state == :active

    assert {:ok, generated} =
             ContactRequirementTemplates.materialize(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               @now,
               DateTime.add(@now, 10_800, :second)
             )

    assert length(generated) == 2

    assert {:ok, closed} =
             ContactRequirementTemplates.close(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               1,
               "Template retired"
             )

    assert closed.lifecycle_state == :closed

    assert {:error, :contact_requirement_template_closed} =
             ContactRequirementTemplates.version(
               context.admin_scope,
               @mission_id,
               template.contact_requirement_template_id,
               1,
               %{requirement_document: requirement_document()}
             )
  end

  test "daily UTC schedules produce stable inclusive occurrences" do
    schedule = %{
      "type" => "daily",
      "anchor_at" => "2026-07-16T00:00:00Z",
      "ends_at" => "2026-07-20T00:00:00Z",
      "time_utc" => "02:30:00",
      "window_offset_seconds" => 0,
      "window_duration_seconds" => 3_600
    }

    assert RequirementSchedule.occurrences_between(
             schedule,
             ~U[2026-07-16 02:30:00Z],
             ~U[2026-07-18 02:30:00Z],
             10
           ) == [
             ~U[2026-07-16 02:30:00.000000Z],
             ~U[2026-07-17 02:30:00.000000Z],
             ~U[2026-07-18 02:30:00.000000Z]
           ]
  end

  defp template_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        spacecraft_id: @spacecraft_id,
        schedule_document: %{
          "type" => "fixed_interval",
          "anchor_at" => DateTime.to_iso8601(@now),
          "interval_seconds" => 3_600,
          "window_offset_seconds" => 600,
          "window_duration_seconds" => 1_800
        },
        requirement_document: requirement_document(),
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 10,
          "maximum_lookback_seconds" => 86_400
        }
      },
      overrides
    )
  end

  defp requirement_document(overrides \\ %{}) do
    Map.merge(
      %{
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
        "rationale" => "Keep payload recorder below mission threshold",
        "metadata" => %{"source" => "recurring-policy"}
      },
      overrides
    )
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "requirement-template-user-#{role}",
        email: "requirement-template-#{role}@example.test",
        display_name: "Requirement Template #{role}"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
