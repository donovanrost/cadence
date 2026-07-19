defmodule Cadence.ContactPlanning.ContactRequirementsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Spacecraft

  @organization_id "org-contact-requirements"
  @mission_id "mission-contact-requirements"
  @spacecraft_id "spacecraft-contact-requirements"
  @now ~U[2026-07-16 20:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: mission.mission_id,
        display_name: "Aurora 3"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    %{
      organization: organization,
      mission: mission,
      member_scope: scope(organization, :member),
      admin_scope: scope(organization, :organization_admin)
    }
  end

  test "an authenticated mission member creates and reads exact Requirement version one", %{
    member_scope: member_scope
  } do
    assert {:ok, requirement, version} =
             ContactRequirements.create(member_scope, @mission_id, requirement_attrs(), now: @now)

    assert requirement.organization_id == @organization_id
    assert requirement.mission_id == @mission_id
    assert requirement.current_version == 1
    assert requirement.lifecycle_state == :active
    assert requirement.created_by == member_scope.user.user_id
    assert requirement.lifecycle_changed_by == member_scope.user.user_id
    assert requirement.lifecycle_reason == "created"

    assert version.version == 1
    assert version.spacecraft_id == @spacecraft_id
    assert version.service_direction == :downlink
    assert version.success_measure == :minimum_data_volume
    assert version.minimum_data_volume_bytes == 1_500_000_000
    assert version.content_sha256 =~ ~r/\A[0-9a-f]{64}\z/

    assert {:ok, fetched_requirement, fetched_version} =
             ContactRequirements.fetch(
               @organization_id,
               @mission_id,
               requirement.contact_requirement_id
             )

    assert fetched_requirement == requirement
    assert fetched_version == version

    assert [{^requirement, ^version}] =
             ContactRequirements.list(@organization_id, @mission_id)
  end

  test "editing inserts one immutable next version and stale edits fail", %{
    member_scope: member_scope
  } do
    assert {:ok, requirement, version_one} =
             ContactRequirements.create(member_scope, @mission_id, requirement_attrs(), now: @now)

    assert {:ok, requirement_two, version_two} =
             ContactRequirements.version(
               member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               %{
                 "priority" => "critical",
                 "minimum_data_volume_bytes" => "2000000000",
                 "rationale" => "Recorder pressure increased"
               },
               now: DateTime.add(@now, 60, :second)
             )

    assert requirement_two.current_version == 2
    assert version_two.version == 2
    assert version_two.priority == :critical
    assert version_two.minimum_data_volume_bytes == 2_000_000_000
    assert version_two.rationale == "Recorder pressure increased"
    refute version_two.content_sha256 == version_one.content_sha256

    assert {:ok, historical} =
             ContactRequirements.fetch_version(
               @organization_id,
               @mission_id,
               requirement.contact_requirement_id,
               1
             )

    assert historical == version_one

    assert {:error, :stale_contact_requirement_version} =
             ContactRequirements.version(
               member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               %{priority: :high}
             )

    assert [latest, oldest] =
             ContactRequirements.list_versions(
               @organization_id,
               @mission_id,
               requirement.contact_requirement_id
             )

    assert {latest.version, oldest.version} == {2, 1}
  end

  test "concurrent edits serialize and only one expected version advances", %{
    member_scope: member_scope
  } do
    assert {:ok, requirement, _version} =
             ContactRequirements.create(member_scope, @mission_id, requirement_attrs(), now: @now)

    results =
      [:high, :critical]
      |> Enum.map(fn priority ->
        Task.async(fn ->
          ContactRequirements.version(
            member_scope,
            @mission_id,
            requirement.contact_requirement_id,
            1,
            %{priority: priority},
            now: DateTime.add(@now, 60, :second)
          )
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(results, &match?({:ok, _requirement, _version}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_contact_requirement_version})) == 1

    assert {:ok, current, current_version} =
             ContactRequirements.fetch(
               @organization_id,
               @mission_id,
               requirement.contact_requirement_id
             )

    assert current.current_version == 2
    assert current_version.priority in [:high, :critical]

    assert ContactRequirements.list_versions(
             @organization_id,
             @mission_id,
             requirement.contact_requirement_id
           )
           |> length() == 2
  end

  test "invalid outcome, window, constraints, and foreign spacecraft fail closed", %{
    member_scope: member_scope
  } do
    assert {:error, {:invalid_contact_requirement, message}} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(%{minimum_data_volume_bytes: nil})
             )

    assert message =~ "minimum_data_volume_bytes is required"

    assert {:error, {:invalid_contact_requirement, message}} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(%{latest_end: @now})
             )

    assert message =~ "latest_end must be after earliest_start"

    assert {:error, :conflicting_contact_requirement_constraints} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(%{
                 provider_constraints_document: %{
                   "allowed" => ["provider-alpha"],
                   "excluded" => ["provider-alpha"]
                 }
               })
             )

    assert {:error, :contact_requirement_spacecraft_not_found} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(%{spacecraft_id: "spacecraft-from-another-mission"})
             )
  end

  test "membership and organization scope protect writes and reads", %{
    organization: organization,
    member_scope: member_scope
  } do
    no_membership_scope =
      Scope.new(%{
        user: User.new(%{email: "outsider@example.test", display_name: "Outsider"}),
        organization_id: organization.organization_id,
        organization: organization
      })

    assert {:error, :forbidden} =
             ContactRequirements.create(no_membership_scope, @mission_id, requirement_attrs())

    assert {:ok, requirement, _version} =
             ContactRequirements.create(member_scope, @mission_id, requirement_attrs(), now: @now)

    assert {:error, :contact_requirement_not_found} =
             ContactRequirements.fetch(
               "org-outside",
               @mission_id,
               requirement.contact_requirement_id
             )
  end

  test "close and cancel require a reason, preserve versions, and block editing", %{
    member_scope: member_scope
  } do
    assert {:ok, requirement, version} =
             ContactRequirements.create(member_scope, @mission_id, requirement_attrs(), now: @now)

    assert {:error, :contact_requirement_transition_reason_required} =
             ContactRequirements.close(
               member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               ""
             )

    assert {:ok, closed} =
             ContactRequirements.close(
               member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               "Mission outcome achieved",
               now: DateTime.add(@now, 120, :second)
             )

    assert closed.lifecycle_state == :closed
    assert closed.lifecycle_reason == "Mission outcome achieved"
    assert closed.current_version == 1

    assert {:error, :contact_requirement_not_active} =
             ContactRequirements.version(
               member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               %{priority: :critical}
             )

    assert [^version] =
             ContactRequirements.list_versions(
               @organization_id,
               @mission_id,
               requirement.contact_requirement_id
             )

    assert [{listed, ^version}] =
             ContactRequirements.list(@organization_id, @mission_id, lifecycle_state: :closed)

    assert listed.lifecycle_state == :closed
  end

  defp requirement_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        spacecraft_id: @spacecraft_id,
        service_direction: :downlink,
        contact_intent: "payload_downlink",
        earliest_start: DateTime.add(@now, 3_600, :second),
        latest_end: DateTime.add(@now, 28_800, :second),
        success_measure: :minimum_data_volume,
        minimum_duration_seconds: 600,
        preferred_duration_seconds: 900,
        minimum_data_volume_bytes: 1_500_000_000,
        contact_count: 1,
        minimum_separation_seconds: 0,
        priority: :high,
        provider_constraints_document: %{
          "allowed" => [],
          "excluded" => []
        },
        station_constraints_document: %{
          "allowed" => [],
          "excluded" => []
        },
        policy_constraints_document: %{},
        approval_policy_document: %{"mode" => "manual"},
        rationale: "Downlink recorder before the next collection period",
        metadata: %{"source" => "operator"}
      },
      overrides
    )
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "contact-requirements-user-#{role}",
        email: "contact-requirements-#{role}@example.test",
        display_name: "Contact Requirements #{role}"
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
