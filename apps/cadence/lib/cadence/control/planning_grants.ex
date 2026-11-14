defmodule Cadence.Control.PlanningGrants do
  @moduledoc """
  Console automation grants (§11 L3; fe-setup's docs/apogee/plans/planning-verbs.md): what lets a
  service identity plan, repair, execute, submit or approve without a person, within the active
  fleet planning policy. Reads for mission operators; issue and revoke for organization admins
  (`AutomationGrants`, Policy `:manage_automation_grants`).

  The console sends back what it read instead of the legacy page's evidence maps: the active
  `policy_version` on issue, the grant's `sha256` on revoke. The server rebuilds the exact
  evidence. `allowed_actions` and the cost limit come from the active policy, as the legacy form
  did (`Applications.OpsConsole.Actions.FleetPlanning.grant_attributes/2`, ported here).
  """

  alias Cadence.{Accounts, Auth}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{AutomationGrants, FleetPlanningPolicies}

  @field_errors %{
    automation_grant_horizon_exceeds_policy:
      {:maximum_horizon_seconds, "is longer than the policy allows"},
    automation_grant_contacts_exceed_policy:
      {:maximum_contacts, "is more than the policy allows"},
    automation_grant_concurrency_exceeds_policy:
      {:maximum_execution_concurrency, "is more than the policy allows"},
    automation_service_identity_disabled: {:service_identity_id, "is disabled"},
    automation_service_identity_scope_mismatch:
      {:service_identity_id, "isn't bound to this mission"},
    automation_grant_already_expired: {:valid_days, "must leave the grant valid in the future"},
    automation_grant_revocation_reason_required: {:reason, "Say why."}
  }

  @spec load(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def load(%Scope{} = scope, mission_id) do
    params = %{organization_id: scope.organization_id, mission_id: mission_id}

    with :ok <- Policy.authorize(scope, :operate_mission, params) do
      org = scope.organization_id
      active = active_policy(org, mission_id)
      identities = Auth.list_service_identities(org, mission_id: mission_id)
      identity_names = Map.new(identities, &{&1.service_identity_id, &1.display_name})
      grants = AutomationGrants.list(org, mission_id)
      users = user_names(grants)
      now = DateTime.utc_now()

      {:ok,
       %{
         grants: Enum.map(grants, &row(&1, identity_names, users, now)),
         service_identities:
           Enum.map(
             identities,
             &%{id: &1.service_identity_id, name: &1.display_name, state: &1.lifecycle_state}
           ),
         policy_version: active && active.version,
         limits: limits(active),
         permissions: permissions(scope)
       }}
    end
  end

  @doc "Issues a grant: `{:ok, row}`, `{:error, {:policy_changed, active_version}}`, or field errors."
  @spec issue(Scope.t(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def issue(%Scope{} = scope, mission_id, params) do
    org = scope.organization_id

    with {:ok, values} <- issue_values(params),
         {:ok, version} <- current_policy(org, mission_id, values.policy_version),
         {:ok, grant} <-
           AutomationGrants.issue(scope, mission_id, attributes(values, version),
             expected_policy: evidence(version)
           ) do
      {:ok, row(grant, %{}, user_names([grant]), DateTime.utc_now()) |> with_identity_name(org)}
    else
      {:error, reason} -> {:error, error(reason)}
    end
  end

  @doc "Revokes a grant read at `sha256`: `{:ok, row}`, `{:error, :grant_changed}`, …"
  @spec revoke(Scope.t(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def revoke(%Scope{} = scope, mission_id, grant_id, params) do
    with {:ok, sha} <- text(params["sha256"], :sha256),
         {:ok, grant} <-
           AutomationGrants.revoke(scope, mission_id, grant_id, sha, params["reason"] || "") do
      {:ok,
       row(grant, %{}, user_names([grant]), DateTime.utc_now())
       |> with_identity_name(scope.organization_id)}
    else
      # A missing sha256 is a field error on sha256 (drift sweep), not on the grant.
      {:error, message} when is_binary(message) -> {:error, {:invalid_params, %{sha256: message}}}
      {:error, reason} -> {:error, error(reason)}
    end
  end

  defp issue_values(params) do
    checks = [
      service_identity_id: text(params["service_identity_id"], :service_identity_id),
      maximum_horizon_seconds:
        positive(params["maximum_horizon_seconds"], :maximum_horizon_seconds),
      maximum_contacts: positive(params["maximum_contacts"], :maximum_contacts),
      maximum_execution_concurrency:
        positive(params["maximum_execution_concurrency"], :maximum_execution_concurrency),
      valid_days: days(params["valid_days"]),
      reason: text(params["reason"], :reason),
      policy_version: positive(params["policy_version"], :policy_version)
    ]

    case for({key, {:error, message}} <- checks, into: %{}, do: {key, message}) do
      errors when errors == %{} ->
        {:ok, Map.new(checks, fn {key, {:ok, value}} -> {key, value} end)}

      errors ->
        {:error, {:invalid_params, errors}}
    end
  end

  defp current_policy(org, mission_id, expected) do
    case active_policy(org, mission_id) do
      %{version: ^expected} = version -> {:ok, version}
      %{version: active} -> {:error, {:policy_changed, active}}
      nil -> {:error, {:policy_changed, nil}}
    end
  end

  defp active_policy(org, mission_id) do
    case FleetPlanningPolicies.fetch_active(org, mission_id) do
      {:ok, _policy, version} -> version
      _none -> nil
    end
  end

  defp evidence(version),
    do: %{
      policy_id: version.fleet_planning_policy_id,
      version: version.version,
      content_sha256: version.content_sha256
    }

  defp attributes(values, policy) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    budget = policy.budget_quota_document || %{}

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
      approval_reason: values.reason
    }
  end

  # What the policy's automation mode lets a grant do (the legacy form's rule).
  defp allowed_actions(policy) do
    automation = policy.automation_repair_document || %{}
    base = [:plan, :repair]
    base = if automation["mode"] != "advisory", do: [:execute | base], else: base
    base = if automation["automatic_submission"], do: [:submit | base], else: base

    if automation["mode"] == "bounded_automatic" and automation["automatic_submission"],
      do: Enum.uniq([:approve | base]),
      else: Enum.uniq(base)
  end

  defp limits(nil),
    do: %{maximum_horizon_seconds: nil, maximum_contacts: nil, maximum_execution_concurrency: nil}

  defp limits(policy),
    do: %{
      maximum_horizon_seconds: (policy.horizon_document || %{})["max_horizon_seconds"],
      maximum_contacts: (policy.budget_quota_document || %{})["max_contacts"],
      maximum_execution_concurrency:
        (policy.automation_repair_document || %{})["execution_concurrency"]
    }

  defp row(grant, identity_names, users, now) do
    %{
      id: grant.automation_grant_id,
      service_identity: %{
        id: grant.service_identity_id,
        name: Map.get(identity_names, grant.service_identity_id)
      },
      policy_version: grant.fleet_planning_policy_version,
      allowed_actions: Enum.map(grant.allowed_actions || [], &to_string/1),
      maximum_horizon_seconds: grant.maximum_horizon_seconds,
      maximum_contacts: grant.maximum_contacts,
      maximum_execution_concurrency: grant.maximum_execution_concurrency,
      maximum_estimated_cost_micros: grant.maximum_estimated_cost_micros,
      currency: grant.currency,
      valid_from: grant.valid_from,
      valid_until: grant.valid_until,
      state: state(grant, now),
      approved_by: person(grant.approved_by, users),
      approved_at: grant.approved_at,
      reason: grant.approval_reason,
      revoked_by: person(grant.revoked_by, users),
      revoked_at: grant.revoked_at,
      revocation_reason: blank(grant.revocation_reason),
      sha256: grant.content_sha256
    }
  end

  # Expired is computed: an active grant past valid_until does nothing.
  defp state(%{lifecycle_state: :revoked}, _now), do: "revoked"

  defp state(%{valid_until: %DateTime{} = until}, now) do
    if DateTime.compare(until, now) == :gt, do: "active", else: "expired"
  end

  defp state(_grant, _now), do: "active"

  defp with_identity_name(row, org) do
    case Auth.fetch_service_identity(org, row.service_identity.id) do
      {:ok, identity} -> put_in(row, [:service_identity, :name], identity.display_name)
      _missing -> row
    end
  end

  defp permissions(scope) do
    if Policy.authorize(scope, :manage_automation_grants, %{
         organization_id: scope.organization_id
       }) == :ok,
       do: ["grants.manage"],
       else: []
  end

  defp user_names(grants) do
    grants
    |> Enum.flat_map(&[&1.approved_by, &1.revoked_by])
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _missing -> {id, nil}
      end
    end)
  end

  defp person(nil, _users), do: nil
  defp person(id, users), do: %{id: id, name: Map.get(users, id)}

  defp error({:invalid_params, _details} = invalid), do: invalid
  defp error({:policy_changed, _active} = changed), do: changed
  defp error(:stale_fleet_planning_policy_evidence), do: :policy_changed
  defp error(:stale_automation_grant_hash), do: :grant_changed
  defp error(:automation_grant_not_found), do: :grant_not_found

  defp error(reason) when is_map_key(@field_errors, reason) do
    {field, message} = Map.fetch!(@field_errors, reason)
    {:invalid_params, %{field => message}}
  end

  defp error({:invalid_automation_grant, message}), do: {:invalid_params, %{grant: message}}
  defp error(reason), do: reason

  defp text(value, _key) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "is required"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp text(_value, :reason), do: {:error, "Say why."}
  defp text(_value, _key), do: {:error, "is required"}

  defp positive(n, _key) when is_integer(n) and n > 0, do: {:ok, n}
  defp positive(_n, _key), do: {:error, "must be a positive integer"}

  defp days(n) when is_integer(n) and n in 1..365, do: {:ok, n}
  defp days(_n), do: {:error, "must be 1 to 365 days"}

  defp blank(""), do: nil
  defp blank(value), do: value
end
