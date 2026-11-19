defmodule Cadence.Applications.OpsConsole.Actions.FleetPlanning do
  @moduledoc "Host actions for the mission-scoped Fleet Planning surfaces."

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
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
    {"fleet_planning_run", "refresh-fleet-run"},
    {"fleet_planning_run", "repair-fleet-run"}
  ]

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
end
