defmodule Cadence.Applications.OpsConsole.Actions.FleetPlanning do
  @moduledoc "Host actions for the mission-scoped Fleet Planning surfaces."

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Applications.OpsConsole.Actions.{FleetPlanningFormDuration, FleetPolicyEditing}
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetPlanningStarts,
    FleetRunActions
  }

  alias Cadence.Missions

  @application_key "ops_console"
  @application_version 1

  @bindings [
    {"fleet_planning", "refresh-planning"},
    {"fleet_planning_new", "validate-fleet-run"},
    {"fleet_planning_new", "create-fleet-run"},
    {"fleet_planning_policy", "validate-policy"},
    {"fleet_planning_policy", "save-policy"},
    {"fleet_planning_policy", "approve-policy"},
    {"fleet_planning_policy", "validate-grant"},
    {"fleet_planning_policy", "issue-grant"},
    {"fleet_planning_policy", "revoke-grant"},
    {"fleet_planning_run", "refresh-fleet-run"},
    {"fleet_planning_run", "repair-fleet-run"}
  ]

  @grant_fields ~w(
    service_identity_id maximum_horizon_duration maximum_contacts
    maximum_execution_concurrency valid_days approval_reason
  )

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @bindings

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(
        %Scope{} = scope,
        %HostContext{} = host_context,
        surface_id,
        %ActionRequest{} = request
      ) do
    with :ok <- validate_request(request),
         :ok <- validate_binding(surface_id, request.action_id),
         {:ok, params} <- bounded_params(request.params),
         {:ok, mission_id} <- validate_context(scope, host_context),
         :ok <- validate_mission_param(mission_id, params),
         :ok <- validate_input(surface_id, request.action_id, params),
         :ok <- authorize(scope, mission_id, surface_id, request.action_id),
         {:ok, value} <- dispatch(scope, mission_id, surface_id, request.action_id, params),
         {:ok, safe_value} <- JSONBoundary.safe(value) do
      {:ok, safe_value}
    else
      false -> {:error, :unsupported_application_action}
      {:error, _reason} = error -> error
      _other -> {:error, :unsupported_application_action}
    end
  rescue
    _exception -> {:error, :unsupported_application_action}
  end

  def execute(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term()
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  defp validate_request(%ActionRequest{
         application_key: @application_key,
         application_version: @application_version,
         action_id: action_id
       })
       when is_binary(action_id) and action_id != "",
       do: :ok

  defp validate_request(_request), do: {:error, :unsupported_application_action}

  defp validate_binding(surface_id, action_id) do
    if is_binary(surface_id) and {surface_id, action_id} in @bindings do
      :ok
    else
      {:error, :unsupported_application_action}
    end
  end

  defp bounded_params(params) when is_map(params) do
    case JSONBoundary.safe(params) do
      {:ok, safe_params} when is_map(safe_params) -> {:ok, safe_params}
      {:ok, _other} -> {:error, :unsupported_application_action}
      {:error, _reason} -> {:error, :unsupported_application_action}
    end
  end

  defp bounded_params(_params), do: {:error, :unsupported_application_action}

  defp validate_context(
         %Scope{organization_id: organization_id, mission_id: scoped_mission_id},
         %HostContext{placement: :mission, mission_id: mission_id} = host_context
       )
       when is_binary(organization_id) and organization_id != "" and
              is_binary(mission_id) and mission_id != "" do
    if HostContext.valid?(host_context) do
      validate_context_mission(scoped_mission_id, organization_id, mission_id)
    else
      {:error, :unsupported_application_action}
    end
  end

  defp validate_context(_scope, _host_context),
    do: {:error, :unsupported_application_action}

  defp validate_context_mission(scoped_mission_id, _organization_id, mission_id)
       when is_binary(scoped_mission_id) and scoped_mission_id != mission_id,
       do: {:error, :scope_mismatch}

  defp validate_context_mission(scoped_mission_id, organization_id, mission_id)
       when is_nil(scoped_mission_id) or is_binary(scoped_mission_id) do
    case Missions.fetch_mission(organization_id, mission_id) do
      {:ok, _mission} -> {:ok, mission_id}
      {:error, _reason} -> {:error, :mission_not_found}
    end
  end

  defp validate_context_mission(_scoped_mission_id, _organization_id, _mission_id),
    do: {:error, :unsupported_application_action}

  defp validate_mission_param(mission_id, params) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      _other -> {:error, :scope_mismatch}
    end
  end

  defp validate_input("fleet_planning", "refresh-planning", params),
    do: exact_map(params, [])

  defp validate_input("fleet_planning_new", "create-fleet-run", params),
    do: FleetPlanningStarts.validate_input(params, :create)

  defp validate_input("fleet_planning_new", "validate-fleet-run", params),
    do: FleetPlanningStarts.validate_input(params, :preview)

  defp validate_input("fleet_planning_policy", action, params)
       when action in ["save-policy", "validate-policy"],
       do: FleetPolicyEditing.validate_input(params)

  defp validate_input("fleet_planning_policy", "approve-policy", params) do
    with :ok <- exact_map(params, ["decision"]),
         {:ok, decision} <- nested_map(params, "decision"),
         :ok <- exact_nested_map(decision, ["reason", "policy_evidence"]),
         {:ok, _reason} <- required_text(decision["reason"]) do
      validate_policy_evidence(decision["policy_evidence"])
    end
  end

  defp validate_input("fleet_planning_policy", "issue-grant", params) do
    with :ok <- exact_map(params, ["grant", "policy_evidence"]),
         :ok <- validate_policy_evidence(params["policy_evidence"]),
         {:ok, grant} <- nested_map(params, "grant"),
         :ok <- exact_nested_map(grant, @grant_fields),
         {:ok, _attrs} <- grant_form_values(grant) do
      :ok
    end
  end

  defp validate_input("fleet_planning_policy", "validate-grant", params) do
    with {:ok, grant} <- nested_map(params, "grant"),
         :ok <- exact_nested_map(grant, @grant_fields),
         {:ok, _values} <- grant_form_values(grant) do
      :ok
    end
  end

  defp validate_input("fleet_planning_policy", "revoke-grant", params) do
    with {:ok, revocation} <- nested_map(params, "revocation"),
         :ok <- exact_nested_map(revocation, ["automation_grant_id", "reason"]),
         {:ok, _grant_id} <- required_text(revocation["automation_grant_id"]),
         {:ok, _reason} <- required_text(revocation["reason"]) do
      :ok
    end
  end

  defp validate_input("fleet_planning_run", "refresh-fleet-run", params),
    do: FleetRunActions.validate(:continue, params)

  defp validate_input("fleet_planning_run", "repair-fleet-run", params),
    do: FleetRunActions.validate(:repair, params)

  defp validate_input(_surface_id, _action_id, _params),
    do: {:error, :unsupported_application_action}

  defp exact_map(params, required, optional \\ [])

  defp exact_map(params, required, optional) when is_map(params) do
    allowed = MapSet.new(["mission_id" | required ++ optional])

    if Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)) and
         Enum.all?(required, &Map.has_key?(params, &1)) do
      :ok
    else
      {:error, :unsupported_application_action}
    end
  end

  defp exact_nested_map(params, required) when is_map(params) do
    if Enum.all?(Map.keys(params), &(&1 in required)) and
         Enum.all?(required, &Map.has_key?(params, &1)) do
      :ok
    else
      {:error, :unsupported_application_action}
    end
  end

  defp nested_map(params, key) do
    case Map.get(params, key) do
      nested when is_map(nested) -> {:ok, nested}
      _other -> {:error, :unsupported_application_action}
    end
  end

  defp authorize(scope, mission_id, _surface_id, action_id)
       when action_id in [
              "refresh-planning",
              "validate-fleet-run",
              "create-fleet-run",
              "refresh-fleet-run",
              "repair-fleet-run"
            ] do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize(scope, mission_id, "fleet_planning_policy", action_id)
       when action_id in ["validate-policy", "validate-grant"] do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize(scope, _mission_id, "fleet_planning_policy", "save-policy") do
    Policy.authorize(scope, :manage_fleet_planning_policy, %{
      organization_id: scope.organization_id
    })
  end

  defp authorize(scope, _mission_id, "fleet_planning_policy", "approve-policy") do
    Policy.authorize(scope, :approve_fleet_planning_policy, %{
      organization_id: scope.organization_id
    })
  end

  defp authorize(scope, _mission_id, "fleet_planning_policy", action_id)
       when action_id in ["issue-grant", "revoke-grant"] do
    Policy.authorize(scope, :manage_automation_grants, %{
      organization_id: scope.organization_id
    })
  end

  defp authorize(_scope, _mission_id, _surface_id, _action_id),
    do: {:error, :unsupported_application_action}

  defp dispatch(scope, mission_id, "fleet_planning", "refresh-planning", params) do
    with :ok <- exact_map(params, []),
         {:ok, active_policy, _active_version} <-
           optional_active_policy(scope.organization_id, mission_id),
         {:ok, _templates} <- active_templates(scope.organization_id, mission_id),
         {:ok, _grants} <- active_grants(scope.organization_id, mission_id) do
      runs = FleetPlanningRuns.list(scope.organization_id, mission_id, limit: 100)

      {:ok,
       %{
         "missionId" => mission_id,
         "runCount" => length(runs),
         "activePolicy" => not is_nil(active_policy)
       }}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_new", "create-fleet-run", params) do
    with {:ok, run, refs} <- FleetPlanningStarts.create(scope, mission_id, params) do
      {:ok,
       %{
         "contract_version" => 1,
         "organization_id" => scope.organization_id,
         "mission_id" => mission_id,
         "fleetPlanningRunId" => run.fleet_planning_run_id,
         "lifecycleState" => Atom.to_string(run.lifecycle_state),
         "phase" => Atom.to_string(run.phase),
         "requirementCount" => length(refs),
         "evidence" => run.input_document["creation_review"]
       }}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_new", "validate-fleet-run", params) do
    with {:ok, review} <- FleetPlanningStarts.preview(scope, mission_id, params),
         do: {:ok, %{"review" => review}}
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "save-policy", params) do
    with {:ok, policy, version} <- FleetPolicyEditing.save(scope, mission_id, params) do
      {:ok, policy_result(policy, version)}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "validate-policy", params) do
    with {:ok, _base, _attrs} <- FleetPolicyEditing.prepare(scope, mission_id, params) do
      {:ok, validation_result("fleet_planning_policy", "validate-policy")}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "approve-policy", params) do
    with {:ok, decision} <- nested_map(params, "decision"),
         {:ok, reason} <- required_text(decision["reason"]),
         {:ok, evidence} <- policy_evidence(scope, mission_id, decision["policy_evidence"]),
         {:ok, approved_policy, approved_version, _approval} <-
           FleetPlanningPolicies.approve(
             scope,
             mission_id,
             evidence.policy_id,
             evidence.version,
             evidence.content_sha256,
             reason
           ) do
      {:ok, policy_result(approved_policy, approved_version)}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "issue-grant", params) do
    with {:ok, grant_params} <- nested_map(params, "grant"),
         {:ok, evidence} <- policy_evidence(scope, mission_id, params["policy_evidence"]),
         {:ok, _policy, policy_version} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         :ok <- exact_policy_evidence(policy_version, evidence),
         {:ok, attrs} <- grant_attributes(grant_params, policy_version),
         {:ok, grant} <-
           AutomationGrants.issue(scope, mission_id, attrs, expected_policy: evidence) do
      {:ok,
       %{
         "automationGrantId" => grant.automation_grant_id,
         "serviceIdentityId" => grant.service_identity_id,
         "lifecycleState" => Atom.to_string(grant.lifecycle_state),
         "fleetPlanningPolicyVersion" => grant.fleet_planning_policy_version
       }}
    end
  end

  defp dispatch(_scope, _mission_id, "fleet_planning_policy", "validate-grant", params) do
    with {:ok, grant} <- nested_map(params, "grant"),
         {:ok, _values} <- grant_form_values(grant) do
      {:ok, validation_result("fleet_planning_policy", "validate-grant")}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "revoke-grant", params) do
    with {:ok, revocation} <- nested_map(params, "revocation"),
         {:ok, grant_id} <- required_text(revocation["automation_grant_id"]),
         {:ok, reason} <- required_text(revocation["reason"]),
         {:ok, grant} <- AutomationGrants.fetch(scope.organization_id, mission_id, grant_id),
         {:ok, revoked} <-
           AutomationGrants.revoke(
             scope,
             mission_id,
             grant.automation_grant_id,
             grant.content_sha256,
             reason
           ) do
      {:ok,
       %{
         "automationGrantId" => revoked.automation_grant_id,
         "lifecycleState" => Atom.to_string(revoked.lifecycle_state)
       }}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_run", "refresh-fleet-run", params),
    do: FleetRunActions.execute(scope, mission_id, :continue, params)

  defp dispatch(scope, mission_id, "fleet_planning_run", "repair-fleet-run", params),
    do: FleetRunActions.execute(scope, mission_id, :repair, params)

  defp dispatch(_scope, _mission_id, _surface_id, _action_id, _params),
    do: {:error, :unsupported_application_action}

  defp optional_active_policy(organization_id, mission_id) do
    case FleetPlanningPolicies.fetch_active(organization_id, mission_id) do
      {:ok, policy, version} -> {:ok, policy, version}
      {:error, :active_fleet_planning_policy_not_found} -> {:ok, nil, nil}
      {:error, _reason} = error -> error
    end
  end

  defp active_templates(organization_id, mission_id) do
    {:ok, ContactRequirementTemplates.list(organization_id, mission_id, lifecycle_state: :active)}
  end

  defp active_grants(organization_id, mission_id) do
    {:ok, AutomationGrants.list(organization_id, mission_id, lifecycle_state: :active)}
  end

  defp policy_result(policy, version) do
    %{
      "fleetPlanningPolicyId" => policy.fleet_planning_policy_id,
      "lifecycleState" => Atom.to_string(policy.lifecycle_state),
      "currentVersion" => policy.current_version,
      "activeVersion" => policy.active_version,
      "fleetPlanningPolicyVersion" => version.version,
      "contentSha256" => version.content_sha256
    }
  end

  defp validation_result(surface_id, action_id) do
    %{
      "surfaceId" => surface_id,
      "actionId" => action_id,
      "valid" => true,
      "errors" => []
    }
  end

  defp validate_policy_evidence(evidence) when is_map(evidence) do
    keys = ~w(contract_version organization_id mission_id policy_id policy_version content_sha256)

    with :ok <- exact_nested_map(evidence, keys),
         true <- evidence["contract_version"] === 1,
         true <- Enum.all?(~w(organization_id mission_id policy_id), &evidence_id?(evidence[&1])),
         version when is_integer(version) and version > 0 and version <= 9_007_199_254_740_991 <-
           evidence["policy_version"],
         hash when is_binary(hash) <- evidence["content_sha256"],
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, hash) do
      :ok
    else
      _ -> {:error, :invalid_fleet_planning_policy_evidence}
    end
  end

  defp validate_policy_evidence(_), do: {:error, :invalid_fleet_planning_policy_evidence}

  defp evidence_id?(value) when is_binary(value),
    do: byte_size(value) in 1..256 and not Regex.match?(~r/[\x00-\x20\x7f]/, value)

  defp evidence_id?(_), do: false

  defp policy_evidence(scope, mission_id, evidence) do
    if evidence["organization_id"] == scope.organization_id and
         evidence["mission_id"] == mission_id do
      {:ok,
       %{
         policy_id: evidence["policy_id"],
         version: evidence["policy_version"],
         content_sha256: evidence["content_sha256"]
       }}
    else
      {:error, :scope_mismatch}
    end
  end

  defp exact_policy_evidence(version, evidence) do
    if evidence == %{
         policy_id: version.fleet_planning_policy_id,
         version: version.version,
         content_sha256: version.content_sha256
       },
       do: :ok,
       else: {:error, :stale_fleet_planning_policy_evidence}
  end

  defp grant_form_values(params) do
    with {:ok, service_identity_id} <- required_text(params["service_identity_id"]),
         {:ok, maximum_horizon_seconds} <-
           FleetPlanningFormDuration.parse(params["maximum_horizon_duration"]),
         {:ok, maximum_contacts} <- positive_integer(params["maximum_contacts"]),
         {:ok, maximum_execution_concurrency} <-
           positive_integer(params["maximum_execution_concurrency"]),
         {:ok, valid_days} <- positive_integer(params["valid_days"]),
         {:ok, approval_reason} <- required_text(params["approval_reason"]) do
      {:ok,
       %{
         service_identity_id: service_identity_id,
         maximum_horizon_seconds: maximum_horizon_seconds,
         maximum_contacts: maximum_contacts,
         maximum_execution_concurrency: maximum_execution_concurrency,
         valid_days: valid_days,
         approval_reason: approval_reason
       }}
    else
      _invalid -> {:error, :invalid_automation_grant_form}
    end
  end

  defp grant_attributes(params, policy) do
    with {:ok, values} <- grant_form_values(params) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      budget = policy.budget_quota_document

      {:ok,
       %{
         service_identity_id: values.service_identity_id,
         allowed_actions: allowed_actions(policy),
         maximum_horizon_seconds: values.maximum_horizon_seconds,
         maximum_contacts: values.maximum_contacts,
         maximum_estimated_cost_micros: budget["max_estimated_cost_micros"],
         currency: budget["currency"],
         maximum_execution_concurrency: values.maximum_execution_concurrency,
         valid_from: now,
         valid_until: DateTime.add(now, values.valid_days, :day),
         approval_reason: values.approval_reason
       }}
    end
  end

  defp allowed_actions(policy) do
    automation = policy.automation_repair_document
    base = [:plan, :repair]
    base = if automation["mode"] != "advisory", do: [:execute | base], else: base
    base = if automation["automatic_submission"], do: [:submit | base], else: base

    base =
      if automation["mode"] == "bounded_automatic" and automation["automatic_submission"],
        do: [:approve | base],
        else: base

    Enum.uniq(base)
  end

  defp required_text(value) when is_binary(value) do
    value = String.trim(value)

    if value == "", do: {:error, :invalid_text}, else: {:ok, value}
  end

  defp required_text(_value), do: {:error, :invalid_text}

  defp positive_integer(value) do
    case integer_value(value) do
      {:ok, integer} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_positive_integer}
    end
  end

  defp integer_value(value) when is_integer(value), do: {:ok, value}

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, :invalid_integer}
    end
  end

  defp integer_value(_value), do: {:error, :invalid_integer}
end
