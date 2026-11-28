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

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    FleetPlanningPolicy,
    FleetPlanningPolicyVersion
  }

  alias Cadence.ContactPlanning.FleetPlanningPolicySchema

  @doc """
  Contact planning's console capabilities for the caller in `mission_id`, one per server action
  (#1160 row 5), each from the very check that action makes (#722 criterion 3), so the two
  can't drift:

  - `planning.template.manage`: template writes and lifecycle moves
    (`ContactRequirementTemplates.authorize_manage/2`, `:manage_mission`);
  - `fleet_planning_policy.manage`: saving a policy version
    (`FleetPlanningPolicies.authorize_manage/1`, `:manage_fleet_planning_policy`);
  - `planning.requirement.edit`: requirement create, update, close and cancel
    (`ContactRequirements.authorize_edit/2`, `:operate_mission`);
  - `planning.approve`: deciding a pending policy version
    (`FleetPlanningPolicies.authorize_approve/1`, `:approve_fleet_planning_policy`).
  """
  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    [
      {"planning.template.manage", &ContactRequirementTemplates.authorize_manage(&1, mission_id)},
      {"fleet_planning_policy.manage", &FleetPlanningPolicies.authorize_manage/1},
      {"planning.requirement.edit", &ContactRequirements.authorize_edit(&1, mission_id)},
      {"planning.approve", &FleetPlanningPolicies.authorize_approve/1}
    ]
    |> Enum.filter(fn {_name, check} -> check.(scope) == :ok end)
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
        pending = pending(organization_id, mission_id, policy, current)

        Map.merge(base, %{
          policy_id: policy.fleet_planning_policy_id,
          # The latest version: the `expected_version` for the next save.
          version: current.version,
          active_version: policy.active_version,
          document: shown_document(organization_id, mission_id, policy, current),
          pending: pending
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
  @spec save(Scope.t(), binary(), map(), pos_integer() | nil, binary() | nil) ::
          {:ok, %{version: pos_integer(), state: :pending_approval}} | {:error, term()}
  def save(%Scope{} = scope, mission_id, document, expected_version, reason \\ nil)
      when is_map(document) do
    with {:ok, reason} <- reason(reason) do
      document
      |> attrs()
      |> Map.put(:reason, reason)
      |> save_attrs(scope, mission_id, expected_version)
    end
  end

  defp save_attrs(attrs, scope, mission_id, expected_version) do
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
           ) do
      # FleetPlanningPolicies refuses the version's author (:reviewer_is_author).
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

  # The latest version awaits review while it isn't active and has no
  # decision (a rejected version stays latest but isn't pending).
  defp pending(organization_id, mission_id, %FleetPlanningPolicy{} = policy, current) do
    decided? =
      organization_id
      |> FleetPlanningPolicies.list_approvals(mission_id, policy.fleet_planning_policy_id)
      |> Enum.any?(&(&1.fleet_planning_policy_version == current.version))

    if policy.active_version != current.version and not decided?,
      do: %{
        version: current.version,
        requested_by:
          actor(
            current.created_by,
            MemberNames.members(organization_id, [current.created_by])
          ),
        requested_at: current.created_at,
        document: document(current),
        reason: current.reason
      }
  end

  # The active version's document; the latest one when nothing is active yet.
  defp shown_document(organization_id, mission_id, policy, current) do
    with active when is_integer(active) and active != current.version <- policy.active_version,
         {:ok, version} <-
           FleetPlanningPolicies.fetch_version(
             organization_id,
             mission_id,
             policy.fleet_planning_policy_id,
             active
           ) do
      document(version)
    else
      _latest -> document(current)
    end
  end

  # #146 (#468): a person is named, and keeps their id, only while an active member of the
  # mission's organization (one batched lookup per read); anyone else reads id and name nil,
  # never an email.
  defp actor(user_id, people) do
    case Map.fetch(people, user_id) do
      {:ok, name} -> %{kind: "user", id: user_id, name: name}
      :error -> %{kind: "user", id: nil, name: nil}
    end
  end

  defp document(version) do
    Map.new(FleetPlanningPolicySchema.groups(), fn {key, attr} ->
      {key, Map.get(version, attr) || %{}}
    end)
  end

  # The saver's note on the version (lead 11-14): optional, at most 500 characters.
  defp reason(nil), do: {:ok, nil}

  defp reason(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> {:ok, nil}
      String.length(trimmed) <= 500 -> {:ok, trimmed}
      true -> {:error, {:invalid_params, %{reason: "Use at most 500 characters."}}}
    end
  end

  defp reason(_other), do: {:error, {:invalid_params, %{reason: "must be text"}}}

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
