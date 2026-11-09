defmodule Cadence.Control.PlanningPolicy do
  @moduledoc """
  Console CP2: the mission's fleet planning policy as one document, saved as
  a new version that needs review, and the review decision.

  A saved version is `pending_approval` until an organization admin who
  didn't author it approves it (`:reviewer_is_author` otherwise); the domain
  (`FleetPlanningPolicies`) validates the document and enforces the admin
  rule. The wire document groups the six policy sections
  (`Cadence.ContactPlanning.FleetPlanningPolicySchema.groups/0`).
  """

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    FleetPlanningPolicies,
    FleetPlanningPolicy,
    FleetPlanningPolicyVersion
  }

  alias Cadence.ContactPlanning.FleetPlanningPolicySchema

  @doc "`planning.edit` / `planning.approve` for the caller (organization admins today)."
  @spec permissions(Scope.t()) :: [binary()]
  def permissions(%Scope{} = scope) do
    params = %{organization_id: scope.organization_id}

    [
      {"planning.edit", :manage_fleet_planning_policy},
      {"planning.approve", :approve_fleet_planning_policy}
    ]
    |> Enum.filter(fn {_name, action} -> Policy.authorize(scope, action, params) == :ok end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec get(binary(), binary()) :: map()
  def get(organization_id, mission_id) do
    base = %{
      schema: FleetPlanningPolicySchema.fields(),
      defaults: FleetPlanningPolicySchema.defaults()
    }

    case FleetPlanningPolicies.fetch(organization_id, mission_id) do
      {:ok, %FleetPlanningPolicy{} = policy, %FleetPlanningPolicyVersion{} = current} ->
        Map.merge(base, %{
          policy_id: policy.fleet_planning_policy_id,
          version: current.version,
          active_version: policy.active_version,
          document: document(current),
          pending: pending(policy, current)
        })

      {:error, _none} ->
        Map.merge(base, %{
          policy_id: nil,
          version: nil,
          active_version: nil,
          document: nil,
          pending: nil
        })
    end
  end

  @doc "Saves `document` as the next version (or the first). `expected_version` guards edits."
  @spec save(Scope.t(), binary(), map(), pos_integer() | nil) ::
          {:ok, %{version: pos_integer(), state: :pending_approval}} | {:error, term()}
  def save(%Scope{} = scope, mission_id, document, expected_version) when is_map(document) do
    attrs = attrs(document)

    result =
      case FleetPlanningPolicies.fetch(scope.organization_id, mission_id) do
        {:error, :fleet_planning_policy_not_found} ->
          FleetPlanningPolicies.create(scope, mission_id, attrs)

        {:ok, policy, current} ->
          if expected_version == current.version,
            do:
              FleetPlanningPolicies.version(
                scope,
                mission_id,
                policy.fleet_planning_policy_id,
                current.version,
                attrs
              ),
            else: {:error, {:version_conflict, current.version}}
      end

    case result do
      {:ok, _policy, version} -> {:ok, %{version: version.version, state: :pending_approval}}
      {:error, _reason} = error -> error
    end
  end

  @doc "Approves or rejects the pending version; the reviewer must not be its author."
  @spec decide(Scope.t(), binary(), pos_integer(), :approve | :reject, binary()) ::
          {:ok, %{version: pos_integer(), state: atom()}} | {:error, term()}
  def decide(%Scope{} = scope, mission_id, number, decision, comment) do
    with {:ok, policy, _current} <- FleetPlanningPolicies.fetch(scope.organization_id, mission_id),
         {:ok, version} <-
           FleetPlanningPolicies.fetch_version(
             scope.organization_id,
             mission_id,
             policy.fleet_planning_policy_id,
             number
           ),
         :ok <- not_author(scope, version) do
      apply_decision(scope, mission_id, policy, version, decision, comment)
    end
  end

  defp apply_decision(scope, mission_id, policy, version, :approve, comment) do
    with {:ok, _policy, _version, _approval} <-
           FleetPlanningPolicies.approve(
             scope,
             mission_id,
             policy.fleet_planning_policy_id,
             version.version,
             version.content_sha256,
             comment
           ),
         do: {:ok, %{version: version.version, state: :active}}
  end

  defp apply_decision(scope, mission_id, policy, version, :reject, comment) do
    with {:ok, _result} <-
           reject(scope, mission_id, policy.fleet_planning_policy_id, version, comment),
         do: {:ok, %{version: version.version, state: :rejected}}
  end

  defp reject(scope, mission_id, policy_id, version, comment) do
    case FleetPlanningPolicies.reject(
           scope,
           mission_id,
           policy_id,
           version.version,
           version.content_sha256,
           comment
         ) do
      {:ok, policy} -> {:ok, policy}
      {:ok, policy, _version, _approval} -> {:ok, policy}
      {:error, _reason} = error -> error
    end
  end

  defp not_author(%Scope{user: %{user_id: user_id}}, %{created_by: user_id}),
    do: {:error, :reviewer_is_author}

  defp not_author(_scope, _version), do: :ok

  defp pending(
         %FleetPlanningPolicy{active_version: active},
         %FleetPlanningPolicyVersion{} = current
       )
       when active != current.version,
       do: %{
         version: current.version,
         requested_by: current.created_by,
         requested_at: current.created_at
       }

  defp pending(_policy, _current), do: nil

  defp document(version) do
    Map.new(FleetPlanningPolicySchema.groups(), fn {key, attr} ->
      {key, Map.get(version, attr) || %{}}
    end)
  end

  defp attrs(document) do
    FleetPlanningPolicySchema.groups()
    |> Enum.flat_map(fn {key, attr} ->
      case Map.fetch(document, key) do
        {:ok, value} -> [{attr, value}]
        :error -> []
      end
    end)
    |> Map.new()
  end
end
