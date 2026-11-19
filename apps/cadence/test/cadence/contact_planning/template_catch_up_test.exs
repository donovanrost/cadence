defmodule Cadence.ContactPlanning.TemplateCatchUpTest do
  @moduledoc """
  The catch-up bounds of a template run (lead, 11-14): `maximum_lookback_seconds` bounds how far
  into the PAST a run reaches, measured from now; the future part of the range is always in scope,
  up to `maximum_occurrences_per_run`. Supersession cancels an older version's requirements only on
  the occurrences the run generated (qa #86 live check).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates}
  alias Cadence.Spacecraft

  @organization_id "org-template-catch-up"
  @mission_id "mission-template-catch-up"
  @spacecraft_id "spacecraft-template-catch-up"
  # Every 6 h from the anchor: 00, 06, 12, 18Z.
  @anchor ~U[2026-07-01 00:00:00.000000Z]
  @now ~U[2026-07-17 01:00:00.000000Z]
  @hour 3_600

  setup do
    %{organization: organization} = persist_mission_scope(@organization_id, @mission_id)

    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        @organization_id,
        Spacecraft.new(%{
          spacecraft_id: @spacecraft_id,
          mission_id: @mission_id,
          display_name: "Catch-up"
        })
      )

    %{scope: scope(organization)}
  end

  describe "a run's occurrences" do
    test "a horizon longer than the lookback is generated in full, not just its last part", c do
      {template, _version} = template!(c, lookback: @hour, cap: 100)

      # A 24 h horizon from now, with a 1 h lookback: 06, 12, 18Z and 00Z the next day. Measured
      # from the range end, only 00Z (the last hour) was generated.
      assert {:ok, results} = materialize(c, template, @now, DateTime.add(@now, 24 * @hour))

      assert occurrence_hours(results) == [
               ~U[2026-07-17 06:00:00.000000Z],
               ~U[2026-07-17 12:00:00.000000Z],
               ~U[2026-07-17 18:00:00.000000Z],
               ~U[2026-07-18 00:00:00.000000Z]
             ]
    end

    test "a catch-up reaches at most the lookback into the past", c do
      {template, _version} = template!(c, lookback: 12 * @hour, cap: 100)

      # From three days back to 12 h ahead: the past part only within 12 h before now (from
      # 13:00Z the day before), the future part in full. Measured from the range end (13:00Z
      # today) the past part was dropped entirely.
      assert {:ok, results} =
               materialize(
                 c,
                 template,
                 DateTime.add(@now, -72 * @hour),
                 DateTime.add(@now, 12 * @hour)
               )

      assert occurrence_hours(results) == [
               ~U[2026-07-16 18:00:00.000000Z],
               ~U[2026-07-17 00:00:00.000000Z],
               ~U[2026-07-17 06:00:00.000000Z],
               ~U[2026-07-17 12:00:00.000000Z]
             ]
    end

    test "the per-run cap bounds the count, earliest first, and says where it stopped", c do
      {template, version} = template!(c, lookback: @hour, cap: 3)

      assert {:ok, results} = materialize(c, template, @now, DateTime.add(@now, 7 * 24 * @hour))
      assert length(results) == 3
      assert List.last(occurrence_hours(results)) == ~U[2026-07-17 18:00:00.000000Z]

      assert {[_, _, last], %{limit: 3, last_at: last}} =
               ContactRequirementTemplates.capped_occurrences(
                 version,
                 @now,
                 DateTime.add(@now, 7 * 24 * @hour),
                 @now
               )

      assert {_all, nil} =
               ContactRequirementTemplates.capped_occurrences(
                 version,
                 @now,
                 DateTime.add(@now, 12 * @hour),
                 @now
               )
    end
  end

  describe "supersession" do
    test "a new version cancels the old version only on the occurrences it generated", c do
      {template, _version} = template!(c, lookback: @hour, cap: 100)

      assert {:ok, v1_results} = materialize(c, template, @now, DateTime.add(@now, 24 * @hour))
      assert length(v1_results) == 4

      # v2 caps a run at one occurrence: it regenerates 06Z only.
      {:ok, _template, _v2} =
        ContactRequirementTemplates.version(c.scope, @mission_id, template, 1, %{
          catch_up_policy_document: %{
            "maximum_occurrences_per_run" => 1,
            "maximum_lookback_seconds" => @hour
          }
        })

      assert {:ok, [_one]} = materialize(c, template, @now, DateTime.add(@now, 24 * @hour))

      by_version =
        @organization_id
        |> ContactRequirements.list(@mission_id, lifecycle_state: :active)
        |> Enum.map(fn {_requirement, version} -> generation(version) end)
        |> Enum.sort()

      # 06Z moved to v2; 12Z, 18Z and 00Z keep their v1 requirement (none is left without one).
      assert by_version == [
               {"2026-07-17T06:00:00.000000Z", 2},
               {"2026-07-17T12:00:00.000000Z", 1},
               {"2026-07-17T18:00:00.000000Z", 1},
               {"2026-07-18T00:00:00.000000Z", 1}
             ]
    end
  end

  defp template!(c, lookback: lookback, cap: cap) do
    {:ok, template, version} =
      ContactRequirementTemplates.create(
        c.scope,
        @mission_id,
        %{
          spacecraft_id: @spacecraft_id,
          schedule_document: %{
            "type" => "fixed_interval",
            "anchor_at" => DateTime.to_iso8601(@anchor),
            "interval_seconds" => 6 * @hour,
            "window_offset_seconds" => 0,
            "window_duration_seconds" => 1_800
          },
          requirement_document: requirement_document(),
          catch_up_policy_document: %{
            "maximum_occurrences_per_run" => cap,
            "maximum_lookback_seconds" => lookback
          }
        },
        now: @now
      )

    {template.contact_requirement_template_id, version}
  end

  defp materialize(c, template_id, from, until),
    do:
      ContactRequirementTemplates.materialize(c.scope, @mission_id, template_id, from, until,
        now: @now
      )

  defp occurrence_hours(results),
    do: results |> Enum.map(& &1.occurrence.occurrence_at) |> Enum.sort(DateTime)

  defp generation(version) do
    generation = version.metadata["generation"]
    {generation["occurrence_at"], generation["contact_requirement_template_version"]}
  end

  defp requirement_document do
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
      "rationale" => "Catch-up bounds",
      "metadata" => %{"source" => "recurring-policy"}
    }
  end

  defp scope(organization) do
    user =
      User.new(%{
        user_id: "template-catch-up-admin",
        email: "template-catch-up@example.test",
        display_name: "Catch-up admin"
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user.user_id,
          organization_id: organization.organization_id,
          role: :organization_admin
        })
    })
  end
end
