defmodule Cadence.Reads.ApplicationSurfaces.PlanningProducersTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningPolicies
  }

  alias Cadence.Management.Contacts.Store.FleetPlanningPolicyRow
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Spacecraft

  @org "org-planning-producers"
  @mission "mission-planning-producers"
  @other_mission "mission-planning-producers-other"
  @craft "craft-planning-producers"
  @checker Path.expand(
             "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
             __DIR__
           )

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, @other_mission)
    %{admin: scope(organization, :organization_admin), member: scope(organization, :member)}
  end

  test "empty member surfaces distinguish absence from administrative authority", context do
    policy = model(context.member, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert policy.props["page"]["manifest"]["empty"]["id"] == "fleet-policy-empty"
    assert policy.props["page"]["state"]["label"] == "stopped"
    assert policy.props["policy_form"] == nil
    assert policy.props["approval_form"] == nil
    assert policy.props["grant_form"] == nil
    assert policy.props["revocation_form"] == nil
    assert policy.props["automation_grants"] == []
    refute policy.props["authorization"]["organization_admin"]

    templates =
      model(context.member, "contact_requirement_template", "OpsContactRequirementTemplate")

    assert templates.props["templates"] == []
    assert templates.props["ledger"]["count"] == 0
    assert templates.props["template_form"] == nil

    assert templates.props["authorization"]["admin_required"]["id"] ==
             "requirement-template-admin-required"

    new = model(context.member, "contact_requirement_new", "OpsContactRequirementNew")
    assert new.props["form"]["fields"]["spacecraft_id"]["options"] == []
    assert new.props["form"]["fields"]["spacecraft_id"]["value"] == ""
    assert new.props["journey"]["outcome"]["id"] == "contact-requirement-outcome-section"
    assert new.props["actions"]["cancel"]["href"] == "/missions/#{@mission}/ops/requirements"

    render_models([
      Map.put(policy, :expected, %{
        presentIds: ["fleet-policy-empty"],
        absentIds: ["fleet-policy-form", "automation-grant-form"]
      }),
      Map.put(templates, :expected, %{
        presentIds: ["requirement-templates-empty", "requirement-template-admin-required"],
        absentIds: ["requirement-template-form"]
      }),
      new
    ])
  end

  test "declaration uses only mission spacecraft and produces a saveable domain form", context do
    persist_craft(@mission, @craft)
    persist_craft(@other_mission, "foreign-craft")
    new = model(context.member, "contact_requirement_new", "OpsContactRequirementNew")
    fields = new.props["form"]["fields"]
    assert map_size(fields) == 16
    assert fields["spacecraft_id"]["options"] == [%{"label" => @craft, "value" => @craft}]
    assert fields["spacecraft_id"]["value"] == @craft
    assert fields["rationale"]["required"]
    assert fields["minimum_data_volume_bytes"]["min"] == "1"
    {:ok, starts} = NaiveDateTime.from_iso8601(fields["earliest_start"]["value"])
    {:ok, ends} = NaiveDateTime.from_iso8601(fields["latest_end"]["value"])
    assert NaiveDateTime.diff(ends, starts) == 86_400

    params = fields |> values() |> Map.put("rationale", "Download recorder before overflow")

    assert {:ok, %{"contactRequirementId" => id}} =
             action(context.member, "contact_requirement_new", "save", %{
               "contact_requirement" => params
             })

    assert {:ok, _, version} = ContactRequirements.fetch(@org, @mission, id)
    assert version.spacecraft_id == @craft
    assert version.minimum_data_volume_bytes == 1_000_000_000
    assert version.rationale == params["rationale"]

    render_models([
      Map.put(new, :expected, %{
        fieldValues: %{
          "requirement-spacecraft" => @craft,
          "requirement-minimum-data-volume" => "1000000000"
        }
      })
    ])
  end

  test "template form creates current domain values and ledger follows lifecycle", context do
    persist_craft(@mission, @craft)
    persist_craft(@other_mission, "foreign-craft")

    initial =
      model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")

    fields = initial.props["template_form"]["fields"]
    assert map_size(fields) == 19

    assert fields["spacecraft_id"]["options"] == [
             %{"label" => "Choose spacecraft", "value" => ""},
             %{"label" => @craft, "value" => @craft}
           ]

    assert Enum.map(fields["priority"]["options"], & &1["value"]) == ~w(critical high routine)

    assert Enum.map(fields["success_measure"]["options"], & &1["value"]) ==
             ~w(minimum_duration minimum_data_volume contact_count any_contact)

    params =
      fields
      |> values()
      |> Map.merge(%{
        "spacecraft_id" => @craft,
        "priority" => "routine",
        "success_measure" => "any_contact",
        "rationale" => "Recurring recorder service"
      })

    assert {:error, :forbidden} =
             action(context.member, "contact_requirement_template", "create-template", %{
               "template" => params
             })

    assert {:ok, _} =
             action(context.admin, "contact_requirement_template", "create-template", %{
               "template" => params
             })

    [{template, version}] = ContactRequirementTemplates.list(@org, @mission)
    id = template.contact_requirement_template_id
    assert version.requirement_document["priority"] == "routine"
    assert version.requirement_document["success_measure"] == "any_contact"
    active = model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")
    [row] = active.props["templates"]
    assert row["id"] == id
    assert row["content_sha256"] == version.content_sha256
    assert row["__dom_id"] == "requirement-template-#{id}"
    assert row["actions"]["pause"]["id"] == "pause-template-#{id}"
    assert active.props["ledger"]["count"] == 1
    assert active.props["ledger"]["empty"] == nil

    reader =
      model(context.member, "contact_requirement_template", "OpsContactRequirementTemplate")

    refute Map.has_key?(hd(reader.props["templates"]), "actions")

    assert {:ok, _} =
             action(context.admin, "contact_requirement_template", "pause-template", %{"id" => id})

    paused = model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")
    assert hd(paused.props["templates"])["lifecycle"]["state"] == "paused"

    assert {:ok, _} =
             action(context.admin, "contact_requirement_template", "activate-template", %{
               "id" => id
             })

    assert {:ok, _} =
             action(context.admin, "contact_requirement_template", "close-template", %{"id" => id})

    closed = model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")

    assert hd(closed.props["templates"])["actions"] == %{
             "pause" => nil,
             "activate" => nil,
             "close" => nil
           }

    render_models([
      initial,
      Map.put(active, :expected, %{
        presentIds: ["requirement-template-#{id}", "pause-template-#{id}"]
      }),
      Map.put(reader, :expected, %{
        presentIds: ["requirement-template-#{id}"],
        absentIds: ["pause-template-#{id}", "requirement-template-form"]
      }),
      Map.put(paused, :expected, %{
        presentIds: ["activate-template-#{id}"],
        absentIds: ["pause-template-#{id}"]
      }),
      Map.put(closed, :expected, %{
        absentIds: ["pause-template-#{id}", "activate-template-#{id}", "close-template-#{id}"]
      })
    ])
  end

  test "policy forms show persisted draft while grants use the approved version", context do
    initial = model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert map_size(initial.props["policy_form"]["fields"]) == 16
    assert initial.props["policy_form"]["open"]
    assert initial.props["approval_form"] == nil

    assert {:ok, policy, v1} =
             FleetPlanningPolicies.create(context.admin, @mission, policy_attrs())

    draft = model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert draft.props["page"]["state"]["label"] == "draft"
    assert draft.props["page"]["manifest"]["content_sha256"] == v1.content_sha256
    assert draft.props["policy_form"]["fields"]["max_horizon_duration"]["value"] == "1d"
    assert draft.props["approval_form"]["submit"]["label"] == "Approve exact v1"
    assert draft.props["grant_form"] == nil
    approve(context.admin, policy, v1)
    identity = persist_identity(@mission, "mission-automation", :active)
    persist_identity(@mission, "disabled-automation", :disabled)
    persist_identity(@other_mission, "other-automation", :active)

    assert {:ok, _, v2} =
             FleetPlanningPolicies.version(
               context.admin,
               @mission,
               policy.fleet_planning_policy_id,
               1,
               %{horizon_document: %{"max_horizon_seconds" => 172_800}}
             )

    next = model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert next.props["policy_form"]["fields"]["max_horizon_duration"]["value"] == "2d"
    assert next.props["page"]["manifest"]["content_sha256"] == v2.content_sha256
    assert next.props["approval_form"]["submit"]["label"] == "Approve exact v2"
    assert next.props["grant_form"]["fields"]["maximum_horizon_duration"]["value"] == "1d"

    assert next.props["grant_form"]["fields"]["service_identity_id"]["options"] ==
             [%{"label" => identity.display_name, "value" => identity.service_identity_id}]

    reader = model(context.member, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert reader.props["policy_form"] == nil
    assert reader.props["grant_form"] == nil
    assert reader.props["page"]["manifest"] == next.props["page"]["manifest"]

    render_models([
      initial,
      draft,
      reader,
      Map.put(next, :expected, %{
        presentIds: ["fleet-policy-approval-form", "automation-grant-form"],
        fieldValues: %{
          "policy-max-horizon-duration" => "2d",
          "grant-max-horizon-duration" => "1d",
          "grant-service-identity" => identity.service_identity_id
        }
      })
    ])
  end

  test "grant ledger and revocation options follow persisted scope and lifecycle", context do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(context.admin, @mission, policy_attrs())

    approve(context.admin, policy, version)
    identity = persist_identity(@mission, "grant-automation", :active)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, grant} =
             AutomationGrants.issue(
               context.admin,
               @mission,
               %{
                 service_identity_id: identity.service_identity_id,
                 allowed_actions: [:plan],
                 maximum_horizon_seconds: 3_600,
                 maximum_contacts: 5,
                 maximum_execution_concurrency: 2,
                 valid_from: now,
                 valid_until: DateTime.add(now, 86_400, :second),
                 approval_reason: "Bounded planning"
               },
               now: now
             )

    active = model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    [row] = active.props["automation_grants"]
    assert row["automation_grant_id"] == grant.automation_grant_id
    assert row["__dom_id"] == "automation-grant-#{grant.automation_grant_id}"
    assert active.props["grant_ledger"]["active_count"] == 1

    assert active.props["revocation_form"]["fields"]["automation_grant_id"]["options"] ==
             [%{"label" => identity.service_identity_id, "value" => grant.automation_grant_id}]

    assert {:ok, _} =
             AutomationGrants.revoke(
               context.admin,
               @mission,
               grant.automation_grant_id,
               grant.content_sha256,
               "Stop automation"
             )

    revoked = model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert revoked.props["grant_ledger"]["active_count"] == 0
    assert revoked.props["revocation_form"] == nil
    assert hd(revoked.props["automation_grants"])["lifecycle_state"] == "revoked"

    other =
      model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy", @other_mission)

    assert other.props["automation_grants"] == []
    render_models([active, revoked, other])
  end

  test "second-based policy boundaries are not truncated in evidence", context do
    assert {:ok, _, _} =
             FleetPlanningPolicies.create(context.admin, @mission, %{
               horizon_document: %{"max_horizon_seconds" => 5_400},
               automation_repair_document: %{"repair_horizon_seconds" => 3_601}
             })

    data = model(context.admin, "fleet_planning_policy", "OpsFleetPlanningPolicy")
    assert data.props["policy_form"]["fields"]["max_horizon_duration"]["value"] == "1h 30m"
    facts = data.props["page"]["manifest"]["sections"] |> Enum.flat_map(& &1["facts"])
    assert %{"term" => "Maximum horizon", "value" => "5400 sec"} in facts
    assert %{"term" => "Repair horizon", "value" => "3601 sec"} in facts
    render_models([data])
  end

  test "template schedules preserve seconds and select the actual current version", context do
    persist_craft(@mission, @craft)
    form = model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")

    params =
      form.props["template_form"]["fields"]
      |> values()
      |> Map.merge(%{
        "spacecraft_id" => @craft,
        "rationale" => "Recurring service"
      })

    assert {:ok, _} =
             action(context.admin, "contact_requirement_template", "create-template", %{
               "template" => params
             })

    [{template, _}] = ContactRequirementTemplates.list(@org, @mission)
    id = template.contact_requirement_template_id

    assert {:ok, _, v2} =
             ContactRequirementTemplates.version(context.admin, @mission, id, 1, %{
               schedule_document: %{
                 "type" => "fixed_interval",
                 "anchor_at" => "2026-09-08T00:00:00Z",
                 "interval_seconds" => 3_601,
                 "window_duration_seconds" => 1_801
               }
             })

    interval =
      model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")

    [row] = interval.props["templates"]
    assert row["schedule"] == "Every 3601 sec · 1801 sec window"
    assert row["content_sha256"] == v2.content_sha256
    assert row["version_label"] == "v2"

    assert {:ok, _, _} =
             ContactRequirementTemplates.version(context.admin, @mission, id, 2, %{
               schedule_document: %{
                 "type" => "daily",
                 "anchor_at" => "2026-09-08T00:00:00Z",
                 "time_utc" => "12:34:56",
                 "window_duration_seconds" => 1_800
               }
             })

    daily = model(context.admin, "contact_requirement_template", "OpsContactRequirementTemplate")
    assert hd(daily.props["templates"])["schedule"] == "Daily at 12:34:56 · 30 min window"

    other =
      model(
        context.admin,
        "contact_requirement_template",
        "OpsContactRequirementTemplate",
        @other_mission
      )

    assert other.props["templates"] == []
    render_models([interval, daily, other])
  end

  test "missing persisted policy versions are unavailable, not an empty policy", context do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(context.admin, @mission, policy_attrs())

    approve(context.admin, policy, version)
    row = Repo.get!(FleetPlanningPolicyRow, policy.fleet_planning_policy_id)

    for field <- [:current_version, :active_version] do
      row |> Ecto.Changeset.change(%{field => 999}) |> Repo.update!()

      assert {:error, :unsupported_application_surface_query} =
               OpsConsole.load(
                 context.admin,
                 HostContext.mission(@mission),
                 request("fleet_planning_policy")
               )

      Repo.get!(FleetPlanningPolicyRow, policy.fleet_planning_policy_id)
      |> Ecto.Changeset.change(%{field => 1})
      |> Repo.update!()

      assert {:ok, _} =
               OpsConsole.load(
                 context.admin,
                 HostContext.mission(@mission),
                 request("fleet_planning_policy")
               )
    end
  end

  test "all repaired reads reject mismatched mission and unauthenticated scopes", context do
    for surface <- ~w(contact_requirement_new contact_requirement_template fleet_planning_policy) do
      for invalid_scope <- [
            %{context.member | mission_id: @other_mission},
            %{context.member | organization_id: "foreign-org"},
            %{context.member | user: nil}
          ] do
        assert {:error, :unsupported_application_surface_query} =
                 OpsConsole.load(invalid_scope, HostContext.mission(@mission), request(surface))
      end
    end
  end

  defp model(scope, surface, component, mission \\ @mission) do
    assert {:ok, %{"data" => %{"presentation" => %{"component" => ^component, "props" => props}}}} =
             OpsConsole.load(scope, HostContext.mission(mission), request(surface))

    %{component: component, props: props}
  end

  defp request(surface),
    do: %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface,
      surface_version: 1,
      query_id: "cadence.ops.#{surface}",
      query_version: 1,
      params: %{}
    }

  defp action(scope, surface, action, params) do
    ContactPlanning.execute(scope, HostContext.mission(@mission), surface, %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action,
      params: params
    })
  end

  defp render_models(models) do
    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @checker, Jason.encode!(models)],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Planning ownership producer/consumer render checks passed"
  end

  defp values(fields), do: Map.new(fields, fn {key, field} -> {key, field["value"]} end)

  defp persist_craft(mission, id) do
    assert {:ok, _} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @org,
               Spacecraft.new(%{spacecraft_id: id, mission_id: mission, display_name: id})
             )
  end

  defp persist_identity(mission, id, state) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: id,
        organization_id: @org,
        mission_id: mission,
        display_name: id,
        lifecycle_state: state,
        capabilities: [:mission_admin]
      })

    assert {:ok, issued} = Auth.issue_service_identity(identity)
    issued.service_identity
  end

  defp approve(scope, policy, version) do
    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               scope,
               @mission,
               policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Approved bounded planning"
             )
  end

  defp policy_attrs,
    do: %{
      horizon_document: %{"max_horizon_seconds" => 86_400},
      budget_quota_document: %{"max_contacts" => 10},
      automation_repair_document: %{
        "mode" => "bounded_automatic",
        "execution_concurrency" => 4,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => true
      }
    }

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "planning-#{role}",
        email: "planning-#{role}@example.test",
        display_name: "Planning #{role}"
      })

    membership =
      OrganizationMembership.new(%{user_id: user.user_id, organization_id: @org, role: role})

    Scope.new(%{
      user: user,
      organization_id: @org,
      organization: organization,
      organization_membership: membership
    })
  end
end
