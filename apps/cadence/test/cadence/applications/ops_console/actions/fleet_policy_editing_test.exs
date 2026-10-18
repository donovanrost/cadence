defmodule Cadence.Applications.OpsConsole.Actions.FleetPolicyEditingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.Actions.FleetPlanning, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.FleetPlanningPolicies
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @org "org-policy-editing"
  @mission "mission-policy-editing"
  @documents ~w(horizon_document scoring_document resource_policy_document budget_quota_document redundancy_document automation_repair_document)a
  @checker Path.expand(
             "../../../../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/decision-producer-check.mjs",
             __DIR__
           )

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)
    %{admin: scope(organization, :organization_admin), member: scope(organization, :member)}
  end

  test "producer and actual Vue save preserve every unedited setting and exact seconds",
       context do
    {:ok, policy, original} = FleetPlanningPolicies.create(context.admin, @mission, rich_attrs())
    props = props(context.admin)
    assert props["policy_form"]["fields"]["max_horizon_duration"]["value"] == "1h 30m"
    assert props["policy_form"]["fields"]["repair_horizon_duration"]["value"] == "1h 1s"
    params = emitted(props, %{"requirement_concurrency" => "5"})

    assert {:ok, %{"fleetPlanningPolicyVersion" => 2}} =
             execute(context.admin, "save-policy", params)

    {:ok, _, saved} = FleetPlanningPolicies.fetch(@org, @mission)
    expected = Map.put(original.horizon_document, "requirement_concurrency", 5)
    assert saved.horizon_document == expected

    for key <- @documents -- [:horizon_document],
        do: assert(Map.fetch!(saved, key) == Map.fetch!(original, key))

    assert {:ok, ^original} =
             FleetPlanningPolicies.fetch_version(
               @org,
               @mission,
               policy.fleet_planning_policy_id,
               1
             )

    assert FleetPlanningPolicies.list_approvals(@org, @mission, policy.fleet_planning_policy_id) ==
             []

    assert {:error, :active_fleet_planning_policy_not_found} =
             FleetPlanningPolicies.fetch_active(@org, @mission)
  end

  test "the initial form creates once, and a stale initial form cannot become an edit", context do
    params = emitted(props(context.admin), %{})
    assert params["edit_reference"]["base"] == nil
    assert params["policy"]["automatic_submission"] == "false"

    assert {:ok, %{"fleetPlanningPolicyVersion" => 1}} =
             execute(context.admin, "save-policy", params)

    assert {:error, :stale_fleet_planning_policy_evidence} =
             execute(context.admin, "save-policy", params)

    assert {:ok, %{current_version: 1}, _} = FleetPlanningPolicies.fetch(@org, @mission)
  end

  test "a stale draft never silently merges into the newer current policy", context do
    {:ok, policy, _} = FleetPlanningPolicies.create(context.admin, @mission, rich_attrs())
    params = params(props(context.admin))

    {:ok, _, newer} =
      FleetPlanningPolicies.version(
        context.admin,
        @mission,
        policy.fleet_planning_policy_id,
        1,
        %{scoring_document: %{"priority_weight" => 9000}}
      )

    for action <- ["validate-policy", "save-policy"] do
      assert {:error, :stale_fleet_planning_policy_evidence} =
               execute(context.admin, action, params)
    end

    assert {:ok, %{current_version: 2}, ^newer} = FleetPlanningPolicies.fetch(@org, @mission)

    assert {:ok, %{"fleetPlanningPolicyVersion" => 3}} =
             execute(context.admin, "save-policy", params(props(context.admin)))

    {:ok, _, saved} = FleetPlanningPolicies.fetch(@org, @mission)
    assert saved.scoring_document == newer.scoring_document
  end

  test "optional overall ceilings and currency for provider budgets round-trip without defaults",
       context do
    attrs =
      Map.put(rich_attrs(), :budget_quota_document, %{
        "currency" => "EUR",
        "per_provider" => %{"provider-a" => %{"max_estimated_cost_micros" => 250}}
      })

    {:ok, _, original} = FleetPlanningPolicies.create(context.admin, @mission, attrs)
    params = params(props(context.admin))
    assert params["policy"]["max_contacts"] == ""
    assert params["policy"]["max_estimated_cost_micros"] == ""
    assert {:ok, _} = execute(context.admin, "save-policy", params)
    {:ok, _, saved} = FleetPlanningPolicies.fetch(@org, @mission)
    for key <- @documents, do: assert(Map.fetch!(saved, key) == Map.fetch!(original, key))
  end

  test "domain validation catches hidden reserve conflicts and malformed or out-of-bound durations",
       context do
    {:ok, _, original} = FleetPlanningPolicies.create(context.admin, @mission, rich_attrs())
    params = params(props(context.admin))

    invalid = [
      {"max_estimated_cost_micros", "1"},
      {"currency", ""},
      {"requirement_concurrency", "65"},
      {"max_contacts", "0"},
      {"automatic_submission", "true"},
      {"max_horizon_duration", "24"},
      {"max_horizon_duration", "1.5h"},
      {"max_horizon_duration", "59s"},
      {"max_horizon_duration", "31d 1s"},
      {"max_horizon_duration", "1h 2h"},
      {"max_horizon_duration", "1m 1h"},
      {"max_horizon_duration", "1h garbage"},
      {"repair_horizon_duration", "-1h"}
    ]

    for {field, value} <- invalid, action <- ["validate-policy", "save-policy"] do
      assert {:error, _} =
               execute(context.admin, action, put_in(params, ["policy", field], value))
    end

    assert {:ok, %{current_version: 1}, ^original} = FleetPlanningPolicies.fetch(@org, @mission)

    valid =
      params
      |> put_in(["policy", "max_horizon_duration"], "1d 2h 3m 4s")
      |> put_in(["policy", "repair_horizon_duration"], "60s")

    assert {:ok, %{"valid" => true}} = execute(context.admin, "validate-policy", valid)
    assert {:ok, %{current_version: 1}, ^original} = FleetPlanningPolicies.fetch(@org, @mission)
    assert {:ok, _} = execute(context.admin, "save-policy", valid)
    {:ok, _, saved} = FleetPlanningPolicies.fetch(@org, @mission)
    assert saved.horizon_document["max_horizon_seconds"] == 93_784
    assert saved.automation_repair_document["repair_horizon_seconds"] == 60
  end

  test "missing, malformed, substituted and wrong-hash references never create a version",
       context do
    {:ok, _, original} = FleetPlanningPolicies.create(context.admin, @mission, rich_attrs())
    params = params(props(context.admin))
    reference = params["edit_reference"]

    invalid = [
      Map.delete(params, "edit_reference"),
      Map.put(params, "extra", true),
      Map.put(params, "edit_reference", nil),
      put_in(params, ["edit_reference", "contract_version"], 2),
      put_in(params, ["edit_reference", "contract_version"], 1.0),
      Map.put(params, "edit_reference", Map.delete(reference, "base")),
      put_in(params, ["edit_reference", "base"], nil),
      put_in(params, ["edit_reference", "base", "content_sha256"], String.duplicate("0", 64)),
      put_in(params, ["edit_reference", "base", "policy_version"], 1.0),
      put_in(params, ["edit_reference", "base", "extra"], true),
      put_in(params, ["policy", "scoring_document"], %{})
    ]

    for input <- invalid, do: assert({:error, _} = execute(context.admin, "save-policy", input))

    for field <- ["organization_id", "mission_id"] do
      input =
        params
        |> put_in(["edit_reference", field], "foreign")
        |> put_in(["edit_reference", "base", field], "foreign")

      assert {:error, :scope_mismatch} = execute(context.admin, "save-policy", input)
    end

    assert {:ok, %{current_version: 1}, ^original} = FleetPlanningPolicies.fetch(@org, @mission)
  end

  test "authority is rechecked and retirement cannot be bypassed by an old editor", context do
    {:ok, policy, original} = FleetPlanningPolicies.create(context.admin, @mission, rich_attrs())
    params = params(props(context.admin))
    assert {:error, :forbidden} = execute(context.member, "save-policy", params)

    assert {:ok, _} =
             FleetPlanningPolicies.retire(
               context.admin,
               @mission,
               policy.fleet_planning_policy_id,
               1,
               "Retire boundary"
             )

    assert {:error, _} = execute(context.admin, "save-policy", params)
    assert {:ok, %{current_version: 1}, ^original} = FleetPlanningPolicies.fetch(@org, @mission)
  end

  defp props(scope) do
    {:ok, %{"data" => %{"presentation" => %{"props" => props}}}} =
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

  defp params(props),
    do: %{
      "edit_reference" => props["policy_form"]["edit_reference"],
      "policy" =>
        Map.new(props["policy_form"]["fields"], fn {key, field} ->
          {key, to_string(field["value"])}
        end)
    }

  defp execute(scope, action, params),
    do:
      Actions.execute(
        scope,
        HostContext.mission(@mission),
        "fleet_planning_policy",
        %ActionRequest{
          application_key: "ops_console",
          application_version: 1,
          action_id: action,
          params: params
        }
      )

  defp emitted(props, values) do
    {output, status} =
      System.cmd(
        System.find_executable("node"),
        [
          "--no-warnings",
          @checker,
          Jason.encode!(%{props: props, action: "save-policy", values: values})
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    line =
      output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "DECISION_PAYLOAD="))

    assert is_binary(line), output
    line |> String.replace_prefix("DECISION_PAYLOAD=", "") |> Jason.decode!()
  end

  defp rich_attrs,
    do: %{
      horizon_document: %{"max_horizon_seconds" => 5400},
      scoring_document: %{"priority_weight" => 2500, "local_improvement_width" => 5},
      resource_policy_document: %{
        "default_exclusive_capacity" => 3,
        "capacities" => %{"antenna-a" => 5}
      },
      budget_quota_document: %{
        "max_contacts" => 50,
        "max_estimated_cost_micros" => 1000,
        "currency" => "EUR",
        "critical_contact_reserve" => 2,
        "critical_cost_reserve_micros" => 300,
        "per_provider" => %{
          "provider-a" => %{"max_contacts" => 20, "max_estimated_cost_micros" => 750}
        }
      },
      automation_repair_document: %{"repair_horizon_seconds" => 3601}
    }

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "user-policy-editing-#{role}",
        email: "editing-#{role}@example.test",
        display_name: "Policy editor"
      })

    membership =
      OrganizationMembership.new(%{user_id: user.user_id, organization_id: @org, role: role})

    Scope.new(%{
      user: user,
      organization: organization,
      organization_id: @org,
      organization_membership: membership
    })
  end
end
