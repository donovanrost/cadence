defmodule Cadence.ContactPlanning.AutomationGrants do
  @moduledoc """
  Propose, inspect and enforce mission automation grants. #283 (ux U105): `issue/4` makes a
  proposal under the mission's 'independent' approval setting, which authorizes nothing until a
  second org admin approves it (`AutomationGrantReview`), and an active grant at once under
  'direct'. `authorize/6` is checked at every use, inside the caller's transaction.
  """

  import Ecto.Query

  alias Cadence.Auth
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    AutomationGrant,
    AutomationGrantDecisions,
    AutomationGrantReview,
    FleetPlanningPolicies
  }

  alias Cadence.Governance.ActivationPolicy

  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Repo

  @spec issue(Scope.t(), binary(), map(), keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def issue(%Scope{} = scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with {:ok, actor_id} <- admin_actor_id(scope),
         :ok <- authorize_admin(scope) do
      # The approval setting is held stable while the proposal records it (#283, M2 evidence).
      ActivationPolicy.with_stable_policy(scope.organization_id, fn ->
        Repo.transaction(fn ->
          issue_or_rollback(scope, mission_id, attrs, actor_id, now, opts)
        end)
      end)
    end
  end

  defdelegate approve(scope, mission_id, grant_id, digest, opts \\ []), to: AutomationGrantReview
  defdelegate reject(scope, mission_id, grant_id, reason, opts \\ []), to: AutomationGrantReview
  defdelegate narrow(scope, mission_id, grant_id, changes, opts \\ []), to: AutomationGrantReview

  defp issue_or_rollback(scope, mission_id, attrs, actor_id, now, opts) do
    case issue_locked(scope, mission_id, attrs, actor_id, now, opts) do
      {:ok, grant} -> grant
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp issue_locked(scope, mission_id, attrs, actor_id, now, opts) do
    with {:ok, _policy, policy_version} <-
           FleetPlanningPolicies.fetch_active_locked(scope.organization_id, mission_id),
         :ok <- expected_policy(policy_version, Keyword.fetch(opts, :expected_policy)),
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
         :ok <- replaces(scope, mission_id, grant),
         :ok <- AutomationGrantReview.confers(scope, mission_id, grant) do
      insert_and_record(scope, grant)
    end
  end

  defp insert_and_record(scope, grant) do
    decision = if grant.lifecycle_state == :active, do: :not_required, else: :proposed

    with {:ok, row} <- grant |> AutomationGrantRow.changeset() |> Repo.insert(),
         grant = AutomationGrantRow.to_domain(row),
         :ok <-
           AutomationGrantDecisions.record(scope, decision, grant, %{
             reason: grant.approval_reason,
             policy: grant.approval_policy,
             decided_at: grant.proposed_at
           }) do
      {:ok, grant}
    end
  end

  # A widening names the active grant it would replace (U105); approval revokes that one.
  defp replaces(_scope, _mission_id, %{replaces_grant_id: nil}), do: :ok

  defp replaces(scope, mission_id, grant) do
    case fetch(scope.organization_id, mission_id, grant.replaces_grant_id) do
      {:ok, %{lifecycle_state: :active, service_identity_id: service}}
      when service == grant.service_identity_id ->
        :ok

      _other ->
        {:error, :automation_grant_replaces_invalid}
    end
  end

  # Trusted domain callers may issue against the active policy without a prior
  # browser review. The host action always supplies an exact expected reference.
  defp expected_policy(_version, :error), do: :ok

  defp expected_policy(version, {:ok, expected}) do
    reference = %{
      policy_id: version.fleet_planning_policy_id,
      version: version.version,
      content_sha256: version.content_sha256
    }

    if expected == reference, do: :ok, else: {:error, :stale_fleet_planning_policy_evidence}
  end

  @doc """
  Revokes an active grant at once (`AutomationGrantReview.revoke/5`). `_read_hash` is what the
  revoker's screen showed; it no longer refuses (ca-security 11-19: a tightening is never refused,
  even if the grant was narrowed meanwhile).
  """
  @spec revoke(Scope.t(), binary(), binary(), binary() | nil, binary() | nil, keyword()) ::
          {:ok, AutomationGrant.t()} | {:error, term()}
  def revoke(%Scope{} = scope, mission_id, grant_id, _read_hash, reason, opts \\ [])
      when is_binary(mission_id) and is_binary(grant_id) and is_list(opts),
      do: AutomationGrantReview.revoke(scope, mission_id, grant_id, reason, opts)

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

  @doc "Authorized live grant ledger, bounded to 25 rows plus a lookahead."
  def list_page(%Scope{} = scope, mission_id, page)
      when is_integer(page) and page in 1..1_000_000 do
    with true <- is_nil(scope.mission_id) or scope.mission_id == mission_id,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }) do
      query =
        from(r in AutomationGrantRow,
          where: r.organization_id == ^scope.organization_id and r.mission_id == ^mission_id
        )

      rows =
        query
        |> order_by([r], desc: r.inserted_at, asc: r.automation_grant_id)
        |> offset(^((page - 1) * 25))
        |> limit(26)
        |> Repo.all()

      active_count = query |> where([r], r.lifecycle_state == "active") |> Repo.aggregate(:count)

      {:ok,
       %{
         page: page,
         more: length(rows) > 25,
         active_count: active_count,
         entries: rows |> Enum.take(25) |> Enum.map(&AutomationGrantRow.to_domain/1)
       }}
    else
      false -> {:error, :scope_mismatch}
      error -> error
    end
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
         {:ok, grant} <- fetch_shared(scope.organization_id, mission_id, grant_id),
         :ok <- grant_actor(grant, scope),
         :ok <- current_layout(grant),
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
        validity_seconds: validity_seconds(attrs),
        lifecycle_state: :proposed,
        proposed_by: actor_id,
        proposed_at: now,
        proposal_expires_at:
          DateTime.add(now, AutomationGrant.proposal_window_seconds(), :second),
        approval_reason: value(attrs, :approval_reason),
        approval_policy: ActivationPolicy.evidence(organization_id, mission_id),
        replaces_grant_id: value(attrs, :replaces_grant_id),
        revocation_reason: ""
      })

    {:ok, direct(grant, actor_id, now)}
  rescue
    error in ArgumentError -> {:error, {:invalid_automation_grant, error.message}}
  end

  # Under 'direct' the proposer's own approval stands (U105: no new refusal under direct): the
  # grant is active at once, its validity starting now.
  defp direct(%AutomationGrant{approval_policy: %{"separation_of_duties" => true}} = grant, _, _),
    do: grant

  defp direct(grant, actor_id, now) do
    grant
    |> Map.from_struct()
    |> Map.merge(%{
      lifecycle_state: :active,
      approved_by: actor_id,
      approved_at: now,
      valid_from: now,
      valid_until: DateTime.add(now, grant.validity_seconds, :second),
      content_sha256: nil
    })
    |> AutomationGrant.new()
  end

  # Validity is a length until approval (#283). Callers that still send a window give its length.
  defp validity_seconds(attrs) do
    case {value(attrs, :validity_seconds), value(attrs, :valid_from), value(attrs, :valid_until)} do
      {seconds, _from, _until} when is_integer(seconds) ->
        seconds

      {nil, %DateTime{} = from, %DateTime{} = until} ->
        DateTime.diff(until, from, :second)

      _missing ->
        nil
    end
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

  # One expiry function for use and read (AutomationGrant.effective_state/2; ca-security).
  defp usable(grant, now) do
    case AutomationGrant.effective_state(grant, now) do
      :active ->
        if DateTime.before?(now, grant.valid_from),
          do: {:error, :automation_grant_not_yet_valid},
          else: :ok

      :revoked ->
        {:error, :automation_grant_revoked}

      :expired when grant.lifecycle_state == :active ->
        {:error, :automation_grant_expired}

      state ->
        {:error, {:automation_grant_not_active, %{state: state}}}
    end
  end

  # DECISIONS #108 (#283): a row whose stored hash isn't its content's hash in today's layout
  # (written before #283, or altered) is refused, never trusted. The dev reset recreates grants.
  defp current_layout(grant) do
    if grant.content_sha256 == AutomationGrant.content_sha256(grant),
      do: :ok,
      else: {:error, :automation_grant_hash_mismatch}
  end

  # Read under a shared lock in the caller's transaction (ca-security): a revoke or narrow
  # (FOR UPDATE) waits for in-flight uses, and the next use sees it.
  defp fetch_shared(organization_id, mission_id, grant_id) do
    AutomationGrantRow
    |> where(
      [grant],
      grant.organization_id == ^organization_id and grant.mission_id == ^mission_id and
        grant.automation_grant_id == ^grant_id
    )
    |> lock("FOR SHARE")
    |> Repo.one()
    |> case do
      nil -> {:error, :automation_grant_not_found}
      row -> {:ok, AutomationGrantRow.to_domain(row)}
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

  defp maybe_filter_state(query, nil), do: query

  defp maybe_filter_state(query, state)
       when state in [:proposed, :active, :rejected, :revoked, :withdrawn],
       do: where(query, [grant], grant.lifecycle_state == ^Atom.to_string(state))

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
