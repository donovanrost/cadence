defmodule Cadence.Applications.OpsConsole.Actions.FleetPolicyDecisionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.Actions.FleetPlanning, as: Actions
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @org "org-policy-decisions"
  @mission "mission-policy-decisions"
  @checker Path.expand(
             "../../../../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/decision-producer-check.mjs",
             __DIR__
           )

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)
    admin = scope(organization, :organization_admin)
    assert {:ok, policy, version} = FleetPlanningPolicies.create(admin, @mission, attrs())
    %{admin: admin, member: scope(organization, :member), policy: policy, version: version}
  end

  test "the actual producer and Vue decision approve exactly the reviewed hash", context do
    props = props(context.admin)
    assert props["approval_form"]["policy_evidence"] == props["page"]["policy_evidence"]
    params = emitted(props, "approve-policy")

    assert params["decision"]["policy_evidence"]["content_sha256"] ==
             context.version.content_sha256

    assert {:ok, %{"fleetPlanningPolicyVersion" => 1}} =
             execute(context.admin, "approve-policy", params)

    [approval] = approvals(context.policy)
    assert approval.content_sha256 == context.version.content_sha256
    assert approval.reason == "Reviewed exact producer evidence"
    assert {:error, _} = execute(context.admin, "approve-policy", params)
    assert length(approvals(context.policy)) == 1
  end

  test "a stale reviewed draft never approves the newer current version", context do
    params = decision(props(context.admin))

    assert {:ok, _, v2} =
             FleetPlanningPolicies.version(
               context.admin,
               @mission,
               context.policy.fleet_planning_policy_id,
               1,
               %{horizon_document: %{"max_horizon_seconds" => 172_800}}
             )

    assert {:error, :stale_fleet_planning_policy_version} =
             execute(context.admin, "approve-policy", params)

    assert approvals(context.policy) == []

    assert {:error, :active_fleet_planning_policy_not_found} =
             FleetPlanningPolicies.fetch_active(@org, @mission)

    assert {:ok, %{"fleetPlanningPolicyVersion" => 2}} =
             execute(context.admin, "approve-policy", decision(props(context.admin)))

    assert hd(approvals(context.policy)).content_sha256 == v2.content_sha256
  end

  test "wrong hashes and policy identities cannot create approval evidence", context do
    reviewed = props(context.admin)["approval_form"]["policy_evidence"]

    for overrides <- [
          %{"content_sha256" => String.duplicate("0", 64)},
          %{"policy_id" => "nonexistent-policy"}
        ] do
      assert {:error, _} =
               execute(context.admin, "approve-policy", %{
                 "decision" => %{
                   "reason" => "Review",
                   "policy_evidence" => Map.merge(reviewed, overrides)
                 }
               })
    end

    assert approvals(context.policy) == []
  end

  test "evidence admission rejects legacy payloads, unknown protocols and scope substitution",
       context do
    reviewed = props(context.admin)["approval_form"]["policy_evidence"]

    assert {:error, _} =
             execute(context.admin, "approve-policy", %{"decision" => %{"reason" => "Legacy"}})

    for bad <- [
          nil,
          %{},
          Map.put(reviewed, "extra", true),
          Map.put(reviewed, "contract_version", 2),
          Map.put(reviewed, "contract_version", 1.0),
          Map.put(reviewed, "policy_version", 0),
          Map.put(reviewed, "policy_version", 1.5),
          Map.put(reviewed, "content_sha256", reviewed["content_sha256"] <> "\n"),
          Map.put(reviewed, "policy_id", String.duplicate("é", 129))
        ] do
      assert {:error, _} =
               execute(context.admin, "approve-policy", %{
                 "decision" => %{"reason" => "Review", "policy_evidence" => bad}
               })
    end

    for field <- ["organization_id", "mission_id"] do
      assert {:error, :scope_mismatch} =
               execute(context.admin, "approve-policy", %{
                 "decision" => %{
                   "reason" => "Review",
                   "policy_evidence" => Map.put(reviewed, field, "foreign")
                 }
               })
    end

    assert approvals(context.policy) == []
  end

  test "every exact decision still requires administrator authority", context do
    params = decision(props(context.admin))
    assert {:error, :forbidden} = execute(context.member, "approve-policy", params)
    approve(context)
    identity()
    reviewed = props(context.admin)
    assert {:error, :forbidden} = execute(context.member, "issue-grant", grant_params(reviewed))
    assert AutomationGrants.list(@org, @mission) == []
  end

  test "actual producer and Vue issuance bind the active policy, not the newer draft", context do
    approve(context)
    identity()

    assert {:ok, _, _} =
             FleetPlanningPolicies.version(
               context.admin,
               @mission,
               context.policy.fleet_planning_policy_id,
               1,
               %{horizon_document: %{"max_horizon_seconds" => 172_800}}
             )

    reviewed = props(context.admin)
    assert reviewed["page"]["policy_evidence"]["policy_version"] == 2
    assert reviewed["grant_form"]["policy_evidence"]["policy_version"] == 1
    params = emitted(reviewed, "issue-grant")

    assert {:ok, %{"fleetPlanningPolicyVersion" => 1}} =
             execute(context.admin, "issue-grant", params)

    [grant] = AutomationGrants.list(@org, @mission)
    assert grant.fleet_planning_policy_version == 1
    assert grant.fleet_planning_policy_id == context.policy.fleet_planning_policy_id
    assert grant.approval_reason == "Reviewed exact producer evidence"
  end

  test "activation after review rejects issuance instead of silently rebinding it", context do
    approve(context)
    identity()
    params = grant_params(props(context.admin))

    assert {:ok, _, v2} =
             FleetPlanningPolicies.version(
               context.admin,
               @mission,
               context.policy.fleet_planning_policy_id,
               1,
               %{horizon_document: %{"max_horizon_seconds" => 172_800}}
             )

    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               context.admin,
               @mission,
               context.policy.fleet_planning_policy_id,
               2,
               v2.content_sha256,
               "New boundary"
             )

    assert {:error, :stale_fleet_planning_policy_evidence} =
             execute(context.admin, "issue-grant", params)

    assert AutomationGrants.list(@org, @mission) == []

    assert {:ok, %{"fleetPlanningPolicyVersion" => 2}} =
             execute(context.admin, "issue-grant", grant_params(props(context.admin)))
  end

  test "grant actions require exact evidence and retirement prevents issuance", context do
    approve(context)
    identity()
    params = grant_params(props(context.admin))

    assert {:error, _} =
             execute(context.admin, "issue-grant", Map.delete(params, "policy_evidence"))

    assert {:error, _} =
             execute(context.admin, "issue-grant", Map.put(params, "unexpected", true))

    assert {:error, :stale_fleet_planning_policy_evidence} =
             execute(
               context.admin,
               "issue-grant",
               put_in(params, ["policy_evidence", "content_sha256"], String.duplicate("0", 64))
             )

    assert {:error, :scope_mismatch} =
             execute(
               context.admin,
               "issue-grant",
               put_in(params, ["policy_evidence", "mission_id"], "another-mission")
             )

    assert {:ok, _} =
             FleetPlanningPolicies.retire(
               context.admin,
               @mission,
               context.policy.fleet_planning_policy_id,
               1,
               "Retire reviewed policy"
             )

    assert {:error, :active_fleet_planning_policy_not_found} =
             execute(context.admin, "issue-grant", params)

    assert AutomationGrants.list(@org, @mission) == []
  end

  for {seconds, displayed} <- [{60, "1m"}, {3601, "1h 1s"}, {5400, "1h 30m"}] do
    @seconds seconds
    @displayed displayed

    test "real producer and native Vue form issue exactly #{seconds} seconds", context do
      identity()
      seconds = @seconds
      displayed = @displayed
      version = activate_horizon(context, seconds)
      reviewed = props(context.admin)
      field = reviewed["grant_form"]["fields"]["maximum_horizon_duration"]
      assert field["value"] == displayed
      assert field["type"] == "text"
      params = emitted(reviewed, "issue-grant")

      assert {:ok, %{"automationGrantId" => grant_id}} =
               execute(context.admin, "issue-grant", params)

      assert {:ok, grant} = AutomationGrants.fetch(@org, @mission, grant_id)
      assert grant.maximum_horizon_seconds == seconds
      assert grant.fleet_planning_policy_version == version.version
      assert params["policy_evidence"]["content_sha256"] == version.content_sha256
    end
  end

  test "a grant may be shorter than one minute but cannot exceed its approved horizon", context do
    identity()
    activate_horizon(context, 60)
    params = grant_params(props(context.admin))
    excessive = put_in(params, ["grant", "maximum_horizon_duration"], "1m 1s")

    assert {:error, :automation_grant_horizon_exceeds_policy} =
             execute(context.admin, "issue-grant", excessive)

    assert AutomationGrants.list(@org, @mission) == []

    short = put_in(params, ["grant", "maximum_horizon_duration"], "1s")
    assert {:ok, _} = execute(context.admin, "validate-grant", Map.take(short, ["grant"]))
    assert AutomationGrants.list(@org, @mission) == []

    assert {:ok, %{"automationGrantId" => grant_id}} =
             execute(context.admin, "issue-grant", short)

    assert {:ok, %{maximum_horizon_seconds: 1}} = AutomationGrants.fetch(@org, @mission, grant_id)
  end

  test "ambiguous, malformed and legacy grant durations never issue authority", context do
    identity()
    approve(context)
    params = grant_params(props(context.admin))

    for bad <- [
          nil,
          1,
          "",
          "0s",
          "24",
          "1.5h",
          "-1s",
          "1h 2h",
          "1m 1h",
          "1h garbage",
          "31d 1s",
          String.duplicate("1", 65) <> "s"
        ] do
      input = put_in(params, ["grant", "maximum_horizon_duration"], bad)
      assert {:error, _} = execute(context.admin, "issue-grant", input)
      assert {:error, _} = execute(context.admin, "validate-grant", Map.take(input, ["grant"]))
    end

    legacy =
      Map.update!(
        params,
        "grant",
        &(Map.delete(&1, "maximum_horizon_duration") |> Map.put("maximum_horizon_hours", "24"))
      )

    assert {:error, _} = execute(context.admin, "issue-grant", legacy)
    assert AutomationGrants.list(@org, @mission) == []
  end

  defp activate_horizon(context, seconds) do
    assert {:ok, current, _} = FleetPlanningPolicies.fetch(@org, @mission)

    assert {:ok, _, version} =
             FleetPlanningPolicies.version(
               context.admin,
               @mission,
               current.fleet_planning_policy_id,
               current.current_version,
               %{horizon_document: %{"max_horizon_seconds" => seconds}}
             )

    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               context.admin,
               @mission,
               current.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Exact horizon boundary"
             )

    version
  end

  defp props(scope) do
    assert {:ok, %{"data" => %{"presentation" => %{"props" => props}}}} =
             OpsConsole.load(scope, HostContext.mission(@mission), %SurfaceQueryRequest{
               application_key: "ops_console",
               application_version: 1,
               surface_id: "fleet_planning_policy",
               surface_version: 1,
               query_id: "cadence.ops.fleet_planning_policy",
               query_version: 1,
               params: %{}
             })

    props
  end

  defp decision(props),
    do: %{
      "decision" => %{
        "reason" => "Reviewed boundary",
        "policy_evidence" => props["approval_form"]["policy_evidence"]
      }
    }

  defp grant_params(props),
    do: %{
      "policy_evidence" => props["grant_form"]["policy_evidence"],
      "grant" =>
        props["grant_form"]["fields"]
        |> Map.new(fn {key, field} -> {key, field["value"]} end)
        |> Map.put("approval_reason", "Reviewed automation authority")
    }

  defp execute(scope, action, params) do
    Actions.execute(scope, HostContext.mission(@mission), "fleet_planning_policy", %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action,
      params: params
    })
  end

  defp emitted(props, action) do
    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @checker, Jason.encode!(%{props: props, action: action})],
        stderr_to_stdout: true
      )

    assert status == 0, output

    line =
      output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "DECISION_PAYLOAD="))

    assert is_binary(line), output
    line |> String.trim_leading("DECISION_PAYLOAD=") |> Jason.decode!()
  end

  defp approvals(policy),
    do: FleetPlanningPolicies.list_approvals(@org, @mission, policy.fleet_planning_policy_id)

  defp approve(context) do
    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               context.admin,
               @mission,
               context.policy.fleet_planning_policy_id,
               1,
               context.version.content_sha256,
               "Initial boundary"
             )
  end

  defp identity do
    assert {:ok, _} =
             Auth.issue_service_identity(
               ServiceIdentity.new(%{
                 service_identity_id: "svc-policy-decisions",
                 organization_id: @org,
                 mission_id: @mission,
                 display_name: "Mission automation",
                 capabilities: [:mission_admin]
               })
             )
  end

  defp attrs,
    do: %{
      horizon_document: %{"max_horizon_seconds" => 86_400},
      budget_quota_document: %{"max_contacts" => 10},
      automation_repair_document: %{
        "mode" => "bounded_automatic",
        "execution_concurrency" => 2,
        "automatic_submission" => true
      }
    }

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "policy-decision-#{role}",
        email: "policy-decision-#{role}@example.test",
        display_name: "Policy decision #{role}"
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
