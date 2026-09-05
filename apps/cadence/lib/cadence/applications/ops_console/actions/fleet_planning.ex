defmodule Cadence.Applications.OpsConsole.Actions.FleetPlanning do
  @moduledoc "Host actions for the mission-scoped Fleet Planning surfaces."

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactPlans,
    ContactRequirementTemplates,
    FleetPlanner,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetRepairs
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

  @policy_fields ~w(
    max_horizon_hours requirement_concurrency provider_search_concurrency
    reuse_freshness_seconds max_contacts max_estimated_cost_micros currency
    critical_contact_reserve automation_mode execution_concurrency max_repair_attempts
    repair_horizon_hours automatic_submission distinct_provider_required
    distinct_station_required distinct_service_pool_required
  )

  @grant_fields ~w(
    service_identity_id maximum_horizon_hours maximum_contacts
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
    cond do
      not HostContext.valid?(host_context) ->
        {:error, :unsupported_application_action}

      is_binary(scoped_mission_id) and scoped_mission_id != mission_id ->
        {:error, :scope_mismatch}

      is_nil(scoped_mission_id) or is_binary(scoped_mission_id) ->
        case Missions.fetch_mission(organization_id, mission_id) do
          {:ok, _mission} -> {:ok, mission_id}
          {:error, _reason} -> {:error, :mission_not_found}
        end

      true ->
        {:error, :unsupported_application_action}
    end
  end

  defp validate_context(_scope, _host_context),
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

  defp validate_input("fleet_planning_new", "create-fleet-run", params) do
    with {:ok, fleet_run} <- nested_map(params, "fleet_run"),
         :ok <- exact_nested_map(fleet_run, ~w(horizon_start horizon_end include_recurring)),
         {:ok, _start} <-
           parse_datetime(fleet_run["horizon_start"], :fleet_planning_horizon_invalid),
         {:ok, _end} <- parse_datetime(fleet_run["horizon_end"], :fleet_planning_horizon_invalid),
         {:ok, _include_recurring} <- json_boolean(fleet_run["include_recurring"]) do
      :ok
    end
  end

  defp validate_input("fleet_planning_new", "validate-fleet-run", params) do
    with {:ok, fleet_run} <- nested_map(params, "fleet_run"),
         :ok <- exact_nested_map(fleet_run, ~w(horizon_start horizon_end include_recurring)),
         {:ok, _start} <-
           parse_datetime(fleet_run["horizon_start"], :fleet_planning_horizon_invalid),
         {:ok, _end} <-
           parse_datetime(fleet_run["horizon_end"], :fleet_planning_horizon_invalid),
         {:ok, _include_recurring} <- json_boolean(fleet_run["include_recurring"]) do
      :ok
    end
  end

  defp validate_input("fleet_planning_policy", "save-policy", params) do
    with {:ok, policy} <- nested_map(params, "policy"),
         :ok <- exact_nested_map(policy, @policy_fields),
         {:ok, _attrs} <- policy_attributes(policy) do
      :ok
    end
  end

  defp validate_input("fleet_planning_policy", "validate-policy", params) do
    with {:ok, policy} <- nested_map(params, "policy"),
         :ok <- exact_nested_map(policy, @policy_fields),
         {:ok, _attrs} <- policy_attributes(policy) do
      :ok
    end
  end

  defp validate_input("fleet_planning_policy", "approve-policy", params) do
    with {:ok, decision} <- nested_map(params, "decision"),
         :ok <- exact_nested_map(decision, ["reason"]),
         {:ok, _reason} <- required_text(decision["reason"]) do
      :ok
    end
  end

  defp validate_input("fleet_planning_policy", "issue-grant", params) do
    with {:ok, grant} <- nested_map(params, "grant"),
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

  defp validate_input("fleet_planning_run", "refresh-fleet-run", params) do
    with :ok <- exact_map(params, ["fleet_planning_run_id"]),
         {:ok, _run_id} <- required_text(params["fleet_planning_run_id"]) do
      :ok
    end
  end

  defp validate_input("fleet_planning_run", "repair-fleet-run", params) do
    with :ok <- exact_map(params, ["fleet_planning_run_id", "repair"]),
         {:ok, _run_id} <- required_text(params["fleet_planning_run_id"]),
         {:ok, repair} <- nested_map(params, "repair"),
         :ok <- exact_nested_map(repair, ~w(horizon_start horizon_end)),
         {:ok, _start} <- parse_datetime(repair["horizon_start"], :fleet_repair_horizon_invalid),
         {:ok, _end} <- parse_datetime(repair["horizon_end"], :fleet_repair_horizon_invalid) do
      :ok
    end
  end

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
    with {:ok, fleet_run} <- nested_map(params, "fleet_run"),
         {:ok, horizon_start} <-
           parse_datetime(fleet_run["horizon_start"], :fleet_planning_horizon_invalid),
         {:ok, horizon_end} <-
           parse_datetime(fleet_run["horizon_end"], :fleet_planning_horizon_invalid),
         {:ok, include_recurring} <- json_boolean(fleet_run["include_recurring"]),
         {:ok, run, refs} <-
           FleetPlanner.start(
             scope,
             mission_id,
             %{
               horizon_start: horizon_start,
               horizon_end: horizon_end,
               trigger_kind: :manual
             },
             materialize_templates: include_recurring
           ) do
      {:ok,
       %{
         "fleetPlanningRunId" => run.fleet_planning_run_id,
         "lifecycleState" => Atom.to_string(run.lifecycle_state),
         "phase" => Atom.to_string(run.phase),
         "requirementCount" => length(refs)
       }}
    end
  end

  defp dispatch(_scope, _mission_id, "fleet_planning_new", "validate-fleet-run", params) do
    with {:ok, fleet_run} <- nested_map(params, "fleet_run"),
         {:ok, _start} <-
           parse_datetime(fleet_run["horizon_start"], :fleet_planning_horizon_invalid),
         {:ok, _end} <- parse_datetime(fleet_run["horizon_end"], :fleet_planning_horizon_invalid),
         {:ok, _include_recurring} <- json_boolean(fleet_run["include_recurring"]) do
      {:ok, validation_result("fleet_planning_new", "validate-fleet-run")}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "save-policy", params) do
    with {:ok, policy_params} <- nested_map(params, "policy"),
         {:ok, attrs} <- policy_attributes(policy_params),
         {:ok, policy, version} <- save_policy(scope, mission_id, attrs) do
      {:ok, policy_result(policy, version)}
    end
  end

  defp dispatch(_scope, _mission_id, "fleet_planning_policy", "validate-policy", params) do
    with {:ok, policy} <- nested_map(params, "policy"),
         {:ok, _attrs} <- policy_attributes(policy) do
      {:ok, validation_result("fleet_planning_policy", "validate-policy")}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "approve-policy", params) do
    with {:ok, decision} <- nested_map(params, "decision"),
         {:ok, reason} <- required_text(decision["reason"]),
         {:ok, policy, version} <- FleetPlanningPolicies.fetch(scope.organization_id, mission_id),
         {:ok, approved_policy, approved_version, _approval} <-
           FleetPlanningPolicies.approve(
             scope,
             mission_id,
             policy.fleet_planning_policy_id,
             version.version,
             version.content_sha256,
             reason
           ) do
      {:ok, policy_result(approved_policy, approved_version)}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_policy", "issue-grant", params) do
    with {:ok, grant_params} <- nested_map(params, "grant"),
         {:ok, _policy, policy_version} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         {:ok, attrs} <- grant_attributes(grant_params, policy_version),
         {:ok, grant} <- AutomationGrants.issue(scope, mission_id, attrs) do
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

  defp dispatch(scope, mission_id, "fleet_planning_run", "refresh-fleet-run", params) do
    with {:ok, run_id} <- required_text(params["fleet_planning_run_id"]),
         {:ok, run} <- FleetPlanningRuns.fetch(scope.organization_id, mission_id, run_id),
         {:ok, result} <- resume_run(scope, mission_id, run) do
      {:ok, run_result(result.run)}
    end
  end

  defp dispatch(scope, mission_id, "fleet_planning_run", "repair-fleet-run", params) do
    with {:ok, run_id} <- required_text(params["fleet_planning_run_id"]),
         {:ok, repair} <- nested_map(params, "repair"),
         {:ok, horizon_start} <-
           parse_datetime(repair["horizon_start"], :fleet_repair_horizon_invalid),
         {:ok, horizon_end} <-
           parse_datetime(repair["horizon_end"], :fleet_repair_horizon_invalid),
         {:ok, run} <- FleetPlanningRuns.fetch(scope.organization_id, mission_id, run_id),
         plan_id when is_binary(plan_id) and plan_id != "" <- run.candidate_contact_plan_id,
         version when is_integer(version) and version > 0 <- run.candidate_contact_plan_version,
         {:ok, plan, _current_version} <-
           ContactPlans.fetch(scope.organization_id, mission_id, plan_id),
         {:ok, repair_run, _refs} <-
           FleetRepairs.start(
             scope,
             mission_id,
             run.fleet_planning_run_id,
             plan.contact_plan_id,
             version,
             %{horizon_start: horizon_start, horizon_end: horizon_end}
           ) do
      {:ok, run_result(repair_run)}
    else
      {:error, _reason} = error -> error
      nil -> {:error, :fleet_repair_plan_missing}
      _invalid_source -> {:error, :fleet_repair_plan_missing}
    end
  end

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

  defp save_policy(scope, mission_id, attrs) do
    case FleetPlanningPolicies.fetch(scope.organization_id, mission_id) do
      {:ok, policy, _current_version} ->
        FleetPlanningPolicies.version(
          scope,
          mission_id,
          policy.fleet_planning_policy_id,
          policy.current_version,
          attrs
        )

      {:error, :fleet_planning_policy_not_found} ->
        FleetPlanningPolicies.create(scope, mission_id, attrs)

      {:error, _reason} = error ->
        error
    end
  end

  defp resume_run(_scope, _mission_id, %{phase: :finished} = run),
    do: {:ok, %{run: run}}

  defp resume_run(scope, mission_id, run) do
    FleetPlanner.run(scope, mission_id, run.fleet_planning_run_id)
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

  defp run_result(run) do
    %{
      "fleetPlanningRunId" => run.fleet_planning_run_id,
      "lifecycleState" => Atom.to_string(run.lifecycle_state),
      "phase" => Atom.to_string(run.phase)
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

  defp policy_attributes(params) do
    with {:ok, max_horizon_hours} <- positive_integer(params["max_horizon_hours"]),
         {:ok, requirement_concurrency} <- positive_integer(params["requirement_concurrency"]),
         {:ok, provider_concurrency} <- positive_integer(params["provider_search_concurrency"]),
         {:ok, reuse_seconds} <- non_negative_integer(params["reuse_freshness_seconds"]),
         {:ok, max_contacts} <- positive_integer(params["max_contacts"]),
         {:ok, max_cost} <- optional_non_negative_integer(params["max_estimated_cost_micros"]),
         {:ok, currency} <- optional_currency(params["currency"]),
         {:ok, critical_reserve} <- non_negative_integer(params["critical_contact_reserve"]),
         {:ok, mode} <- required_string(params["automation_mode"]),
         {:ok, execution_concurrency} <- positive_integer(params["execution_concurrency"]),
         {:ok, repair_attempts} <- non_negative_integer(params["max_repair_attempts"]),
         {:ok, repair_horizon_hours} <- positive_integer(params["repair_horizon_hours"]),
         {:ok, automatic_submission} <- json_boolean(params["automatic_submission"]),
         {:ok, distinct_provider} <- json_boolean(params["distinct_provider_required"]),
         {:ok, distinct_station} <- json_boolean(params["distinct_station_required"]),
         {:ok, distinct_service_pool} <- json_boolean(params["distinct_service_pool_required"]) do
      automatic_submission = mode != "advisory" and automatic_submission

      {:ok,
       %{
         horizon_document: %{
           "max_horizon_seconds" => max_horizon_hours * 3_600,
           "requirement_concurrency" => requirement_concurrency,
           "provider_search_concurrency" => provider_concurrency,
           "reuse_freshness_seconds" => reuse_seconds
         },
         scoring_document: %{},
         resource_policy_document: %{},
         budget_quota_document: %{
           "max_contacts" => max_contacts,
           "max_estimated_cost_micros" => max_cost,
           "currency" => if(max_cost, do: currency || "USD", else: nil),
           "per_provider" => %{},
           "critical_contact_reserve" => critical_reserve,
           "critical_cost_reserve_micros" => 0
         },
         redundancy_document: %{
           "distinct_provider_required" => distinct_provider,
           "distinct_station_required" => distinct_station,
           "distinct_service_pool_required" => distinct_service_pool
         },
         automation_repair_document: %{
           "mode" => mode,
           "execution_concurrency" => execution_concurrency,
           "max_repair_attempts" => repair_attempts,
           "repair_horizon_seconds" => repair_horizon_hours * 3_600,
           "automatic_submission" => automatic_submission
         }
       }}
    else
      _invalid -> {:error, :invalid_fleet_policy_form}
    end
  end

  defp grant_form_values(params) do
    with {:ok, service_identity_id} <- required_text(params["service_identity_id"]),
         {:ok, maximum_horizon_hours} <- positive_integer(params["maximum_horizon_hours"]),
         {:ok, maximum_contacts} <- positive_integer(params["maximum_contacts"]),
         {:ok, maximum_execution_concurrency} <-
           positive_integer(params["maximum_execution_concurrency"]),
         {:ok, valid_days} <- positive_integer(params["valid_days"]),
         {:ok, approval_reason} <- required_text(params["approval_reason"]) do
      {:ok,
       %{
         service_identity_id: service_identity_id,
         maximum_horizon_hours: maximum_horizon_hours,
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
         maximum_horizon_seconds: values.maximum_horizon_hours * 3_600,
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

  defp parse_datetime(value, error) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} ->
        case DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, datetime} -> {:ok, datetime}
          _other -> {:error, error}
        end

      {:error, _reason} ->
        {:error, error}
    end
  end

  defp parse_datetime(_value, error), do: {:error, error}

  defp required_text(value) when is_binary(value) do
    value = String.trim(value)

    if value == "", do: {:error, :invalid_text}, else: {:ok, value}
  end

  defp required_text(_value), do: {:error, :invalid_text}

  defp required_string(value) when is_binary(value), do: {:ok, value}
  defp required_string(_value), do: {:error, :invalid_text}

  defp optional_currency(value) when value in [nil, ""], do: {:ok, nil}

  defp optional_currency(value) when is_binary(value),
    do: {:ok, value |> String.trim() |> String.upcase()}

  defp optional_currency(_value), do: {:error, :invalid_text}

  defp positive_integer(value) do
    case integer_value(value) do
      {:ok, integer} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_positive_integer}
    end
  end

  defp non_negative_integer(value) do
    case integer_value(value) do
      {:ok, integer} when integer >= 0 -> {:ok, integer}
      _other -> {:error, :invalid_non_negative_integer}
    end
  end

  defp optional_non_negative_integer(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_non_negative_integer(value), do: non_negative_integer(value)

  defp integer_value(value) when is_integer(value), do: {:ok, value}

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, :invalid_integer}
    end
  end

  defp integer_value(_value), do: {:error, :invalid_integer}

  defp json_boolean(value) when is_boolean(value), do: {:ok, value}
  defp json_boolean(value) when value in ["true", "on", "1"], do: {:ok, true}
  defp json_boolean(value) when value in ["false", "off", "0"], do: {:ok, false}
  defp json_boolean(_value), do: {:error, :invalid_boolean}
end
