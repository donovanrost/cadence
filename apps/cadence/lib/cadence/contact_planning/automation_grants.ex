defmodule Cadence.ContactPlanning.AutomationGrants do
  @moduledoc "Issue, revoke, inspect, and enforce exact mission automation authorization."

  import Ecto.Query

  alias Cadence.Auth
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    AutomationGrant,
    FleetPlanningPolicies
  }

  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Repo

  @spec issue(Scope.t(), binary(), map(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def issue(%Scope{} = scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_admin(scope),
         {:ok, actor_id} <- admin_actor_id(scope),
         {:ok, _policy, policy_version} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         {:ok, service_identity} <-
           Auth.fetch_service_identity(
             scope.organization_id,
             value(attrs, :service_identity_id)
           ),
         :ok <- service_identity_ready(service_identity, mission_id),
         {:ok, grant} <-
           build_grant(
             scope.organization_id,
             mission_id,
             service_identity.service_identity_id,
             policy_version,
             actor_id,
             attrs,
             now
           ),
         :ok <- grant_within_policy(grant, policy_version),
         :ok <- valid_for_future(grant, now) do
      grant
      |> AutomationGrantRow.changeset()
      |> Repo.insert()
      |> case do
        {:ok, row} -> {:ok, AutomationGrantRow.to_domain(row)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec revoke(Scope.t(), binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def revoke(%Scope{} = scope, mission_id, grant_id, expected_hash, reason, opts \\ [])
      when is_binary(mission_id) and is_binary(grant_id) and is_binary(expected_hash) and
             is_list(opts) do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_admin(scope),
         {:ok, actor_id} <- admin_actor_id(scope),
         :ok <- require_reason(reason) do
      revoke_transaction(
        scope.organization_id,
        mission_id,
        grant_id,
        expected_hash,
        reason,
        actor_id,
        now
      )
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def fetch(organization_id, mission_id, grant_id) do
    case Repo.get_by(AutomationGrantRow,
           organization_id: organization_id,
           mission_id: mission_id,
           automation_grant_id: grant_id
         ) do
      nil -> {:error, :automation_grant_not_found}
      row -> {:ok, AutomationGrantRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [AutomationGrant.t()]
  def list(organization_id, mission_id, opts \\ []) do
    AutomationGrantRow
    |> where(
      [grant],
      grant.organization_id == ^organization_id and grant.mission_id == ^mission_id
    )
    |> maybe_filter_state(opts[:lifecycle_state])
    |> order_by([grant], desc: grant.inserted_at, asc: grant.automation_grant_id)
    |> Repo.all()
    |> Enum.map(&AutomationGrantRow.to_domain/1)
  end

  @spec authorize(Scope.t(), binary(), binary(), AutomationGrant.action(), map(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def authorize(scope, mission_id, grant_id, action, evidence, opts \\ [])

  def authorize(
        %Scope{} = scope,
        mission_id,
        grant_id,
        action,
        evidence,
        opts
      )
      when is_binary(mission_id) and is_binary(grant_id) and is_atom(action) and
             is_map(evidence) and is_list(opts) do
    now = now(opts)

    with :ok <- service_actor(scope, mission_id),
         {:ok, grant} <- fetch(scope.organization_id, mission_id, grant_id),
         :ok <- grant_actor(grant, scope),
         :ok <- usable(grant, now),
         :ok <- action_allowed(grant, action),
         {:ok, _policy, active_policy} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         :ok <- exact_policy(grant, active_policy),
         :ok <- evidence_within_grant(grant, action, evidence) do
      {:ok, grant}
    end
  end

  def authorize(_scope, _mission_id, _grant_id, _action, _evidence, _opts),
    do: {:error, :invalid_automation_authorization}

  defp build_grant(
         organization_id,
         mission_id,
         service_identity_id,
         policy,
         actor_id,
         attrs,
         now
       ) do
    grant =
      AutomationGrant.new(%{
        automation_grant_id:
          value(attrs, :automation_grant_id, Cadence.Ids.new("automation_grant")),
        organization_id: organization_id,
        mission_id: mission_id,
        service_identity_id: service_identity_id,
        fleet_planning_policy_id: policy.fleet_planning_policy_id,
        fleet_planning_policy_version: policy.version,
        allowed_actions: value(attrs, :allowed_actions),
        maximum_horizon_seconds: value(attrs, :maximum_horizon_seconds),
        maximum_contacts: value(attrs, :maximum_contacts),
        maximum_estimated_cost_micros: value(attrs, :maximum_estimated_cost_micros),
        currency: value(attrs, :currency),
        maximum_execution_concurrency: value(attrs, :maximum_execution_concurrency),
        valid_from: value(attrs, :valid_from, now),
        valid_until: value(attrs, :valid_until),
        lifecycle_state: :active,
        approved_by: actor_id,
        approved_at: now,
        approval_reason: value(attrs, :approval_reason),
        revocation_reason: ""
      })

    {:ok, grant}
  rescue
    error in ArgumentError -> {:error, {:invalid_automation_grant, error.message}}
  end

  defp grant_within_policy(grant, policy) do
    allowed_actions = allowed_policy_actions(policy)
    policy_budget = policy.budget_quota_document

    cond do
      not Enum.all?(grant.allowed_actions, &(&1 in allowed_actions)) ->
        {:error, :automation_grant_action_exceeds_policy}

      grant.maximum_horizon_seconds > policy.horizon_document["max_horizon_seconds"] ->
        {:error, :automation_grant_horizon_exceeds_policy}

      exceeds_optional?(
        grant.maximum_contacts,
        policy_budget["max_contacts"]
      ) ->
        {:error, :automation_grant_contacts_exceed_policy}

      exceeds_optional?(
        grant.maximum_estimated_cost_micros,
        policy_budget["max_estimated_cost_micros"]
      ) ->
        {:error, :automation_grant_cost_exceeds_policy}

      policy_budget["currency"] &&
          grant.currency != policy_budget["currency"] ->
        {:error, :automation_grant_currency_differs_from_policy}

      grant.maximum_execution_concurrency >
          policy.automation_repair_document["execution_concurrency"] ->
        {:error, :automation_grant_concurrency_exceeds_policy}

      true ->
        :ok
    end
  end

  defp allowed_policy_actions(policy) do
    automation = policy.automation_repair_document

    base =
      case automation["mode"] do
        "advisory" -> [:plan, :repair]
        "approval_required" -> [:plan, :repair, :execute]
        "bounded_automatic" -> [:plan, :repair, :execute]
      end

    base =
      if automation["automatic_submission"],
        do: [:submit | base],
        else: base

    if automation["mode"] == "bounded_automatic" and automation["automatic_submission"],
      do: [:approve | base],
      else: base
  end

  defp evidence_within_grant(grant, action, evidence) do
    with :ok <-
           required_bound(
             action in [:plan, :repair],
             evidence,
             :horizon_seconds,
             grant.maximum_horizon_seconds,
             :automation_grant_horizon_evidence_required,
             :automation_grant_horizon_exceeded
           ),
         :ok <-
           required_bound(
             action in [:submit, :approve, :execute],
             evidence,
             :contact_count,
             grant.maximum_contacts,
             :automation_grant_contact_evidence_required,
             :automation_grant_contact_limit_exceeded
           ),
         :ok <- cost_bound(grant, action, evidence) do
      required_bound(
        action == :execute,
        evidence,
        :execution_concurrency,
        grant.maximum_execution_concurrency,
        :automation_grant_concurrency_evidence_required,
        :automation_grant_concurrency_exceeded
      )
    end
  end

  defp required_bound(false, _evidence, _field, _maximum, _missing, _exceeded), do: :ok

  defp required_bound(true, evidence, field, maximum, missing, exceeded) do
    case value(evidence, field) do
      amount when is_integer(amount) and amount >= 0 ->
        if amount <= maximum, do: :ok, else: {:error, exceeded}

      _amount ->
        {:error, missing}
    end
  end

  defp cost_bound(%{maximum_estimated_cost_micros: nil}, _action, _evidence), do: :ok
  defp cost_bound(_grant, action, _evidence) when action in [:plan, :repair], do: :ok

  defp cost_bound(grant, _action, evidence) do
    case {
      value(evidence, :estimated_cost_micros),
      value(evidence, :currency)
    } do
      {cost, currency}
      when is_integer(cost) and cost >= 0 and is_binary(currency) ->
        cond do
          String.upcase(currency) != grant.currency ->
            {:error, :automation_grant_currency_mismatch}

          cost > grant.maximum_estimated_cost_micros ->
            {:error, :automation_grant_cost_limit_exceeded}

          true ->
            :ok
        end

      _evidence ->
        {:error, :automation_grant_cost_evidence_required}
    end
  end

  defp service_identity_ready(
         %{lifecycle_state: :active, mission_id: mission_id},
         mission_id
       ),
       do: :ok

  defp service_identity_ready(%{lifecycle_state: :disabled}, _mission_id),
    do: {:error, :automation_service_identity_disabled}

  defp service_identity_ready(_identity, _mission_id),
    do: {:error, :automation_service_identity_scope_mismatch}

  defp service_actor(
         %Scope{
           actor_kind: :service,
           mission_id: mission_id,
           service_identity: %{lifecycle_state: :active, mission_id: mission_id}
         },
         mission_id
       ),
       do: :ok

  defp service_actor(%Scope{}, _mission_id),
    do: {:error, :automation_service_actor_required}

  defp grant_actor(grant, scope) do
    if grant.service_identity_id == scope.service_identity.service_identity_id,
      do: :ok,
      else: {:error, :automation_grant_actor_mismatch}
  end

  defp usable(%{lifecycle_state: :revoked}, _now), do: {:error, :automation_grant_revoked}

  defp usable(grant, now) do
    cond do
      DateTime.before?(now, grant.valid_from) -> {:error, :automation_grant_not_yet_valid}
      not DateTime.before?(now, grant.valid_until) -> {:error, :automation_grant_expired}
      true -> :ok
    end
  end

  defp action_allowed(grant, action) do
    if action in grant.allowed_actions,
      do: :ok,
      else: {:error, :automation_grant_action_not_allowed}
  end

  defp exact_policy(grant, active_policy) do
    if grant.fleet_planning_policy_id == active_policy.fleet_planning_policy_id and
         grant.fleet_planning_policy_version == active_policy.version,
       do: :ok,
       else: {:error, :automation_grant_policy_drift}
  end

  defp valid_for_future(grant, now) do
    if DateTime.after?(grant.valid_until, now),
      do: :ok,
      else: {:error, :automation_grant_already_expired}
  end

  defp exceeds_optional?(_value, nil), do: false
  defp exceeds_optional?(nil, _maximum), do: false
  defp exceeds_optional?(value, maximum), do: value > maximum

  defp authorize_admin(scope) do
    Policy.authorize(scope, :manage_automation_grants, %{
      organization_id: scope.organization_id
    })
  end

  defp admin_actor_id(%Scope{actor_kind: :user, user: %{user_id: user_id}}),
    do: {:ok, user_id}

  defp admin_actor_id(%Scope{}), do: {:error, :authenticated_user_required}

  defp revoke_transaction(
         organization_id,
         mission_id,
         grant_id,
         expected_hash,
         reason,
         actor_id,
         now
       ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_grant(organization_id, mission_id, grant_id),
           :ok <- active_grant(row),
           :ok <- exact_hash(row, expected_hash),
           {:ok, revoked} <-
             row
             |> AutomationGrantRow.revocation_changeset(%{
               lifecycle_state: "revoked",
               revoked_by: actor_id,
               revoked_at: now,
               revocation_reason: reason
             })
             |> Repo.update() do
        AutomationGrantRow.to_domain(revoked)
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> normalize_transaction()
  end

  defp lock_grant(organization_id, mission_id, grant_id) do
    case AutomationGrantRow
         |> where(
           [grant],
           grant.organization_id == ^organization_id and grant.mission_id == ^mission_id and
             grant.automation_grant_id == ^grant_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :automation_grant_not_found}
      row -> {:ok, row}
    end
  end

  defp active_grant(%AutomationGrantRow{lifecycle_state: "active"}), do: :ok
  defp active_grant(_row), do: {:error, :automation_grant_revoked}

  defp exact_hash(%AutomationGrantRow{content_sha256: hash}, hash), do: :ok
  defp exact_hash(_row, _hash), do: {:error, :stale_automation_grant_hash}

  defp require_reason(""), do: {:error, :automation_grant_revocation_reason_required}
  defp require_reason(_reason), do: :ok

  defp maybe_filter_state(query, nil), do: query

  defp maybe_filter_state(query, state) when state in [:active, :revoked],
    do: where(query, [grant], grant.lifecycle_state == ^Atom.to_string(state))

  defp normalize_transaction({:ok, grant}), do: {:ok, grant}
  defp normalize_transaction({:error, reason}), do: {:error, reason}

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
