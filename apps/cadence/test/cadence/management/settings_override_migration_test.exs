defmodule Cadence.Management.SettingsOverrideMigrationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Commanding.WorkspaceSettings
  alias Cadence.Management.{PassReviewSettingsSection, SettingsOverrideMigration}
  alias Cadence.Platform.{PassReviewSettings, ScopedSettings}
  alias Cadence.Reads.OrganizationAudit.SettingsEvents

  setup do
    org = "override-org-#{System.unique_integer([:positive])}"
    mission = "override-mission-#{System.unique_integer([:positive])}"
    persist_mission_scope(org, mission)
    # The settings saved here include the approval setting at the organization level, which
    # only an organization admin may change (#233); this test is about the per-field migration.
    scope = %{member(org, "maya") | capabilities: MapSet.new([:organization_admin])}

    save(scope, nil, ActivationPolicy, %{
      "value" => %{"approval_requirement" => "independent"},
      "allow_override" => true
    })

    save(scope, nil, PassReviewSettingsSection, %{
      "value" => %{"pass_realized_threshold" => 0.95, "realization_target" => 0.98},
      "allow_override" => true
    })

    # Today's full-copy overrides: Governance equal to the org, Pass review with one field
    # changed, Commanding equal to the default.
    save(scope, mission, ActivationPolicy, %{
      "value" => %{"approval_requirement" => "independent"}
    })

    save(scope, mission, PassReviewSettingsSection, %{
      "value" => %{"pass_realized_threshold" => 0.9, "realization_target" => 0.98}
    })

    save(scope, mission, WorkspaceSettings, %{"value" => %{"shelf" => "expanded"}})

    %{org: org, mission: mission, scope: scope}
  end

  test "the dry run keeps differing and governance fields and writes nothing", c do
    before = ScopedSettings.mission_overrides()
    %{plan: plan, report: report} = SettingsOverrideMigration.dry_run()
    assert ScopedSettings.mission_overrides() == before

    assert %{governance_kept?: true, sections: sections} = mission_plan(plan, c.mission)

    assert [
             %{section_id: "cadence.governance", status: :unchanged, inheriting: []} = governance,
             %{section_id: "cadence.pass_review", status: :rewrite} = pass_review,
             %{section_id: "commanding.defaults", status: :rewrite} = commanding
           ] = sections

    assert governance.kept == ["approval_requirement"]
    assert governance.governance_kept == ["approval_requirement"]
    assert pass_review.kept == ["pass_realized_threshold"]
    assert pass_review.inheriting == ["realization_target"]
    assert {commanding.kept, commanding.inheriting} == {[], ["shelf"]}

    assert report =~ "kept explicitly (governance, equals the org): approval_requirement"
    assert report =~ "kept (differs): pass_realized_threshold = 0.9 (organization: 0.95)"
    assert report =~ "now inheriting (equals the org): realization_target"
    assert report =~ "Approval settings stay set for this mission"
  end

  test "the run stores only the kept fields; the rest follow the organization", c do
    governance = ActivationPolicy.load(c.org, c.mission)
    %{plan: plan} = SettingsOverrideMigration.dry_run()

    assert [%{written: ["cadence.pass_review", "commanding.defaults"], stale: []}] =
             plan |> only(c.mission) |> SettingsOverrideMigration.run()

    # Governance isn't written: its token (pending approvals' evidence) is unchanged.
    assert ActivationPolicy.load(c.org, c.mission).token == governance.token

    pass_review = PassReviewSettings.load(c.org, c.mission)
    assert pass_review.saved == %{"pass_realized_threshold" => 0.9}

    assert pass_review.effective == %{
             "pass_realized_threshold" => 0.9,
             "realization_target" => 0.98
           }

    assert WorkspaceSettings.load(c.org, c.mission).source == "inherited"

    save(c.scope, nil, PassReviewSettingsSection, %{
      "value" => %{"pass_realized_threshold" => 0.95, "realization_target" => 0.97},
      "allow_override" => true
    })

    assert PassReviewSettings.effective(c.org, c.mission) == %{threshold: 0.9, target: 0.97}

    # A second run has nothing to rewrite.
    assert %{sections: sections} = mission_plan(SettingsOverrideMigration.plan(), c.mission)
    refute Enum.any?(sections, &(&1.status == :rewrite))
  end

  test "the audit shows one entry for the mission, by the system", c do
    %{plan: plan} = SettingsOverrideMigration.dry_run()
    plan |> only(c.mission) |> SettingsOverrideMigration.run()

    events = SettingsEvents.list(c.org, c.mission, %{id: c.mission, name: "M"})
    migrated = Enum.filter(events, &is_nil(&1.actor))

    assert [%{action: action, target: nil, kind: "config"}] = migrated

    assert action ==
             "Settings now follow the organization except the fields set for this mission. " <>
               "Approval settings stay set for this mission, even where they match the organization."

    # The three earlier saves stay as their own entries.
    assert length(events) == 4
  end

  test "a section that moved since the plan is left alone", c do
    %{plan: plan} = SettingsOverrideMigration.dry_run()

    save(c.scope, c.mission, WorkspaceSettings, %{"value" => %{"shelf" => "minimized"}})

    assert [%{written: ["cadence.pass_review"], stale: ["commanding.defaults"]}] =
             plan |> only(c.mission) |> SettingsOverrideMigration.run()

    assert WorkspaceSettings.load(c.org, c.mission).saved == %{"shelf" => "minimized"}
  end

  # The live :4011 case (director 11-13): only a differing governance field, so the run is a no-op.
  test "a plan with nothing to rewrite runs without writing a revision or an audit entry", c do
    quiet = c.mission <> "-quiet"
    persist_mission_scope(c.org, quiet)
    save(c.scope, quiet, ActivationPolicy, %{"value" => %{"approval_requirement" => "direct"}})
    history = ScopedSettings.history(c.org, quiet, "cadence.governance")

    %{plan: plan, report: report} = SettingsOverrideMigration.dry_run()

    assert %{sections: [%{status: :unchanged, kept: ["approval_requirement"]}]} =
             mission_plan(plan, quiet)

    assert report =~ "No change: nothing is written and no audit entry is made."

    assert [%{mission_id: ^quiet, written: [], stale: []}] =
             plan |> only(quiet) |> SettingsOverrideMigration.run()

    assert ScopedSettings.history(c.org, quiet, "cadence.governance") == history
    refute Enum.any?(SettingsEvents.list(c.org, quiet, nil), &is_nil(&1.actor))
  end

  defp mission_plan(plan, mission), do: Enum.find(plan, &(&1.mission_id == mission))
  defp only(plan, mission), do: Enum.filter(plan, &(&1.mission_id == mission))

  defp save(scope, mission, provider, input) do
    current = provider.settings_snapshot(scope.organization_id, mission)
    assert {:ok, _} = provider.save(scope, mission, current.token, input)
  end

  defp member(org, id) do
    Scope.new(%{
      user: User.new(%{user_id: id, email: id <> "@example.test", display_name: id}),
      organization_id: org,
      organization_membership: OrganizationMembership.new(%{organization_id: org, user_id: id})
    })
  end
end
