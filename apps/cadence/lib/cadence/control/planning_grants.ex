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

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{AutomationGrant, AutomationGrantReview, AutomationGrants}
  alias Cadence.ContactPlanning.FleetPlanningPolicies
  alias Cadence.Governance.ActivationPolicy

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
      users = user_names(org, grants)
      now = DateTime.utc_now()

      {:ok,
       %{
         grants:
           Enum.map(grants, &(&1 |> row(identity_names, users, now) |> flags(scope, &1, now))),
         # #283 (U105): the sheet's words follow the mission's approval setting.
         approval_setting: approval_setting(org, mission_id),
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
      {:ok, render(scope, grant)}
    else
      {:error, reason} -> {:error, error(reason)}
    end
  end

  @doc false
  # One grant as the read renders it, with the viewer's flags: the answer a decision returns and
  # stores for replay (`PlanningGrantDecisions`), so it's JSON-encoded and decoded once here.
  @spec encode_row(Scope.t(), AutomationGrant.t()) :: map()
  def encode_row(%Scope{} = scope, grant),
    do: scope |> render(grant) |> Jason.encode!() |> Jason.decode!()

  defp render(scope, grant) do
    now = DateTime.utc_now()

    grant
    |> row(%{}, user_names(scope.organization_id, [grant]), now)
    |> with_identity_name(scope.organization_id)
    |> flags(scope, grant, now)
  end

  # U105: viewer_can_decide and cannot_decide_because from the server, never the console.
  defp flags(row, scope, grant, now) do
    {because, details} =
      case AutomationGrantReview.viewer_block(scope, grant, now) do
        nil -> {nil, nil}
        blocked -> blocked
      end

    Map.merge(row, %{
      viewer_can_decide: is_nil(because),
      cannot_decide_because: because,
      cannot_decide_details: details
    })
  end

  defp approval_setting(org, mission_id) do
    if ActivationPolicy.evidence(org, mission_id)["separation_of_duties"] == true,
      do: "independent",
      else: "direct"
  end

  @doc "Revokes an active grant at once: `{:ok, row}` or a refusal (never for a reason or hash)."
  @spec revoke(Scope.t(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def revoke(%Scope{} = scope, mission_id, grant_id, params) do
    # #283 (ca-security): a revoke is never refused for want of a reason or a current hash;
    # `sha256` is still accepted and ignored, and a reason is recorded when given.
    case AutomationGrants.revoke(scope, mission_id, grant_id, params["sha256"], params["reason"]) do
      {:ok, grant} -> {:ok, render(scope, grant)}
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
      replaces_grant_id: optional_text(params["replaces_grant_id"]),
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
    budget = policy.budget_quota_document || %{}

    %{
      service_identity_id: values.service_identity_id,
      allowed_actions: allowed_actions(policy),
      maximum_horizon_seconds: values.maximum_horizon_seconds,
      maximum_contacts: values.maximum_contacts,
      maximum_estimated_cost_micros: budget["max_estimated_cost_micros"],
      currency: budget["currency"],
      maximum_execution_concurrency: values.maximum_execution_concurrency,
      # Validity starts at approval (#283): a length, not a window.
      validity_seconds: values.valid_days * 86_400,
      replaces_grant_id: values.replaces_grant_id,
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
      validity_seconds: grant.validity_seconds,
      valid_from: grant.valid_from,
      valid_until: grant.valid_until,
      # One function decides expiry for use and read (AutomationGrant.effective_state/2).
      state: grant |> AutomationGrant.effective_state(now) |> to_string(),
      # A grant issued before #283 had no proposal: its proposal fields read null and it says
      # so (lead and ca-security on #497), never a proposer or time copied from its approval.
      issued_before_two_person_approval: grant.legacy_issue,
      proposed_by: if(grant.legacy_issue, do: nil, else: person(grant.proposed_by, users)),
      proposed_at: if(grant.legacy_issue, do: nil, else: grant.proposed_at),
      proposal_expires_at: if(grant.legacy_issue, do: nil, else: grant.proposal_expires_at),
      approved_by: person(grant.approved_by, users),
      approved_at: grant.approved_at,
      reason: grant.approval_reason,
      replaces_grant_id: grant.replaces_grant_id,
      sha256: grant.content_sha256
    }
    |> Map.merge(ended(grant, users))
  end

  # U105's rejected, withdrawn and revoked fields: who, when and why, both-or-none per state.
  @no_ending %{
    rejected_by: nil,
    rejected_at: nil,
    rejection_reason: nil,
    withdrawn_by: nil,
    withdrawn_at: nil,
    revoked_by: nil,
    revoked_at: nil,
    revocation_reason: nil
  }

  defp ended(%{lifecycle_state: :rejected, ending: e}, users),
    do: %{
      @no_ending
      | rejected_by: person(e.by, users),
        rejected_at: e.at,
        rejection_reason: e.reason
    }

  defp ended(%{lifecycle_state: :withdrawn, ending: e}, users),
    do: %{@no_ending | withdrawn_by: person(e.by, users), withdrawn_at: e.at}

  defp ended(%{lifecycle_state: :revoked, ending: e}, users),
    do: %{
      @no_ending
      | revoked_by: person(e.by, users),
        revoked_at: e.at,
        revocation_reason: e.reason
    }

  defp ended(_grant, _users), do: @no_ending

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

  # #146's rule (#462): people are named only as active members of the organization, never by
  # email; anyone else reads {id: nil, name: nil}, recorded but not identified.
  defp user_names(org, grants) do
    ids =
      grants
      |> Enum.flat_map(&[&1.proposed_by, &1.approved_by, &1.ending && &1.ending.by])
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&is_binary/1)

    MemberNames.display_names(org, ids)
  end

  defp person(nil, _users), do: nil

  defp person(id, users) do
    case Map.fetch(users, id) do
      {:ok, name} -> %{id: id, name: name}
      :error -> %{id: nil, name: nil}
    end
  end

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

  defp optional_text(value) when is_binary(value) and value != "", do: {:ok, value}
  defp optional_text(_value), do: {:ok, nil}

  defp days(n) when is_integer(n) and n in 1..365, do: {:ok, n}
  defp days(_n), do: {:error, "must be 1 to 365 days"}
end
