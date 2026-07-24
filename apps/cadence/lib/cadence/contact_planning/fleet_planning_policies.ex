defmodule Cadence.ContactPlanning.FleetPlanningPolicies do
  @moduledoc "Authorized versioning and activation boundary for mission fleet-planning policy."

  import Ecto.Query

  alias Ecto.{Changeset, Multi}

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    FleetPlanningPolicy,
    FleetPlanningPolicyApproval,
    FleetPlanningPolicyVersion
  }

  alias Cadence.Missions

  alias Cadence.Management.Contacts.Store.{
    FleetPlanningPolicyApprovalRow,
    FleetPlanningPolicyRow,
    FleetPlanningPolicyVersionRow
  }

  alias Cadence.Repo

  @content_fields [
    :horizon_document,
    :scoring_document,
    :resource_policy_document,
    :budget_quota_document,
    :redundancy_document,
    :automation_repair_document
  ]

  @document_limit 128 * 1_024

  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, FleetPlanningPolicy.t(), FleetPlanningPolicyVersion.t()} | {:error, term()}
  def create(%Scope{} = scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_manage(scope),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(scope),
         policy_id <-
           value(attrs, :fleet_planning_policy_id, Cadence.Ids.new("fleet_planning_policy")),
         {:ok, version} <-
           build_version(
             attrs,
             scope.organization_id,
             mission_id,
             policy_id,
             1,
             actor_id,
             now
           ),
         :ok <- validate_document_size(version) do
      policy =
        FleetPlanningPolicy.new(%{
          fleet_planning_policy_id: policy_id,
          organization_id: scope.organization_id,
          mission_id: mission_id,
          current_version: 1,
          active_version: nil,
          lifecycle_state: :draft,
          created_by: actor_id,
          lifecycle_changed_by: actor_id,
          lifecycle_changed_at: now,
          lifecycle_reason: "created"
        })

      Multi.new()
      |> Multi.insert(:policy, FleetPlanningPolicyRow.changeset(policy))
      |> Multi.insert(:version, FleetPlanningPolicyVersionRow.changeset(version))
      |> Repo.transaction()
      |> normalize_create_result()
    end
  end

  @spec version(Scope.t(), binary(), binary(), pos_integer(), map(), keyword()) ::
          {:ok, FleetPlanningPolicy.t(), FleetPlanningPolicyVersion.t()} | {:error, term()}
  def version(
        %Scope{} = scope,
        mission_id,
        policy_id,
        expected_version,
        attrs,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(policy_id) and is_integer(expected_version) and
             expected_version > 0 and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_manage(scope),
         {:ok, actor_id} <- actor_id(scope) do
      Repo.transaction(fn ->
        version_transaction(
          scope.organization_id,
          mission_id,
          policy_id,
          expected_version,
          attrs,
          actor_id,
          now
        )
      end)
      |> normalize_version_result()
    end
  end

  @spec approve(
          Scope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) ::
          {:ok, FleetPlanningPolicy.t(), FleetPlanningPolicyVersion.t(),
           FleetPlanningPolicyApproval.t()}
          | {:error, term()}
  def approve(scope, mission_id, policy_id, version, hash, reason, opts \\ []) do
    decide(scope, mission_id, policy_id, version, hash, :approved, reason, opts)
  end

  @spec reject(
          Scope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) ::
          {:ok, FleetPlanningPolicy.t(), FleetPlanningPolicyVersion.t(),
           FleetPlanningPolicyApproval.t()}
          | {:error, term()}
  def reject(scope, mission_id, policy_id, version, hash, reason, opts \\ []) do
    decide(scope, mission_id, policy_id, version, hash, :rejected, reason, opts)
  end

  @spec retire(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, FleetPlanningPolicy.t()} | {:error, term()}
  def retire(%Scope{} = scope, mission_id, policy_id, expected_version, reason, opts \\ []) do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_manage(scope),
         {:ok, actor_id} <- actor_id(scope),
         :ok <- require_reason(reason) do
      retire_transaction(
        scope.organization_id,
        mission_id,
        policy_id,
        expected_version,
        reason,
        actor_id,
        now
      )
    end
  end

  @spec fetch(binary(), binary()) ::
          {:ok, FleetPlanningPolicy.t(), FleetPlanningPolicyVersion.t()} | {:error, term()}
  def fetch(organization_id, mission_id) do
    case Repo.get_by(FleetPlanningPolicyRow,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      nil ->
        {:error, :fleet_planning_policy_not_found}

      row ->
        with {:ok, version} <- fetch_version_row(row, row.current_version) do
          {:ok, FleetPlanningPolicyRow.to_domain(row),
           FleetPlanningPolicyVersionRow.to_domain(version)}
        end
    end
  end

  @spec fetch_active(binary(), binary()) ::
          {:ok, FleetPlanningPolicy.t(), FleetPlanningPolicyVersion.t()} | {:error, term()}
  def fetch_active(organization_id, mission_id) do
    case Repo.get_by(FleetPlanningPolicyRow,
           organization_id: organization_id,
           mission_id: mission_id,
           lifecycle_state: "active"
         ) do
      %FleetPlanningPolicyRow{active_version: version} = row when is_integer(version) ->
        with {:ok, version_row} <- fetch_version_row(row, version) do
          {:ok, FleetPlanningPolicyRow.to_domain(row),
           FleetPlanningPolicyVersionRow.to_domain(version_row)}
        end

      _row ->
        {:error, :active_fleet_planning_policy_not_found}
    end
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, FleetPlanningPolicyVersion.t()} | {:error, term()}
  def fetch_version(organization_id, mission_id, policy_id, version)
      when is_integer(version) and version > 0 do
    case Repo.get_by(FleetPlanningPolicyVersionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           fleet_planning_policy_id: policy_id,
           version: version
         ) do
      nil -> {:error, :fleet_planning_policy_version_not_found}
      row -> {:ok, FleetPlanningPolicyVersionRow.to_domain(row)}
    end
  end

  @spec list_versions(binary(), binary(), binary()) :: [FleetPlanningPolicyVersion.t()]
  def list_versions(organization_id, mission_id, policy_id) do
    FleetPlanningPolicyVersionRow
    |> where(
      [version],
      version.organization_id == ^organization_id and version.mission_id == ^mission_id and
        version.fleet_planning_policy_id == ^policy_id
    )
    |> order_by([version], desc: version.version)
    |> Repo.all()
    |> Enum.map(&FleetPlanningPolicyVersionRow.to_domain/1)
  end

  @spec list_approvals(binary(), binary(), binary()) :: [FleetPlanningPolicyApproval.t()]
  def list_approvals(organization_id, mission_id, policy_id) do
    FleetPlanningPolicyApprovalRow
    |> where(
      [approval],
      approval.organization_id == ^organization_id and approval.mission_id == ^mission_id and
        approval.fleet_planning_policy_id == ^policy_id
    )
    |> order_by([approval], desc: approval.fleet_planning_policy_version)
    |> Repo.all()
    |> Enum.map(&FleetPlanningPolicyApprovalRow.to_domain/1)
  end

  defp version_transaction(
         organization_id,
         mission_id,
         policy_id,
         expected,
         attrs,
         actor_id,
         now
       ) do
    with {:ok, row} <- lock_policy(organization_id, mission_id, policy_id),
         :ok <- not_retired(row),
         :ok <- expected_version(row, expected),
         {:ok, current_row} <- fetch_version_row(row, row.current_version),
         current <- FleetPlanningPolicyVersionRow.to_domain(current_row),
         merged <- merge_content(current, attrs),
         {:ok, next_version} <-
           build_version(
             merged,
             organization_id,
             mission_id,
             policy_id,
             row.current_version + 1,
             actor_id,
             now
           ),
         :ok <- validate_document_size(next_version),
         {:ok, version_row} <- Repo.insert(FleetPlanningPolicyVersionRow.changeset(next_version)),
         {:ok, updated} <-
           update_projection(row, %{
             current_version: next_version.version,
             active_version: row.active_version,
             lifecycle_state: row.lifecycle_state,
             lifecycle_changed_by: actor_id,
             lifecycle_changed_at: now,
             lifecycle_reason: "versioned"
           }) do
      {FleetPlanningPolicyRow.to_domain(updated),
       FleetPlanningPolicyVersionRow.to_domain(version_row)}
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp decide(
         %Scope{} = scope,
         mission_id,
         policy_id,
         expected_version,
         expected_hash,
         decision,
         reason,
         opts
       )
       when decision in [:approved, :rejected] and is_integer(expected_version) and
              expected_version > 0 and is_binary(expected_hash) do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_approve(scope),
         {:ok, actor} <- actor(scope),
         :ok <- require_reason(reason) do
      decision_context = %{
        mission_id: mission_id,
        policy_id: policy_id,
        expected_version: expected_version,
        expected_hash: expected_hash,
        decision: decision,
        reason: reason,
        actor: actor,
        now: now
      }

      Repo.transaction(fn ->
        decide_transaction(scope.organization_id, decision_context)
      end)
      |> normalize_decision_result()
    end
  end

  defp decide(_scope, _mission_id, _policy_id, _version, _hash, _decision, _reason, _opts),
    do: {:error, :invalid_fleet_planning_policy_decision}

  defp decide_transaction(organization_id, context) do
    with {:ok, row} <-
           lock_policy(organization_id, context.mission_id, context.policy_id),
         :ok <- not_retired(row),
         :ok <- expected_version(row, context.expected_version),
         {:ok, version_row} <- fetch_version_row(row, context.expected_version),
         :ok <- exact_hash(version_row, context.expected_hash),
         :ok <- undecided(row, context.expected_version),
         version <- FleetPlanningPolicyVersionRow.to_domain(version_row),
         approval <-
           build_approval(
             row,
             version,
             context.decision,
             context.reason,
             context.actor,
             context.now
           ),
         {:ok, approval_row} <-
           Repo.insert(FleetPlanningPolicyApprovalRow.changeset(approval)),
         {:ok, updated} <-
           project_decision(
             row,
             version,
             context.decision,
             context.actor,
             context.reason,
             context.now
           ) do
      {
        FleetPlanningPolicyRow.to_domain(updated),
        version,
        FleetPlanningPolicyApprovalRow.to_domain(approval_row)
      }
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp retire_transaction(
         organization_id,
         mission_id,
         policy_id,
         expected_version,
         reason,
         actor_id,
         now
       ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_policy(organization_id, mission_id, policy_id),
           :ok <- expected_version(row, expected_version),
           :ok <- not_retired(row),
           {:ok, updated} <-
             update_projection(row, %{
               current_version: row.current_version,
               active_version: nil,
               lifecycle_state: "retired",
               lifecycle_changed_by: actor_id,
               lifecycle_changed_at: now,
               lifecycle_reason: reason
             }) do
        FleetPlanningPolicyRow.to_domain(updated)
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> normalize_single_result()
  end

  defp project_decision(row, version, :approved, actor, reason, now) do
    update_projection(row, %{
      current_version: row.current_version,
      active_version: version.version,
      lifecycle_state: "active",
      lifecycle_changed_by: actor["user_id"],
      lifecycle_changed_at: now,
      lifecycle_reason: reason
    })
  end

  defp project_decision(row, _version, :rejected, actor, reason, now) do
    state = if row.active_version, do: "active", else: "draft"

    update_projection(row, %{
      current_version: row.current_version,
      active_version: row.active_version,
      lifecycle_state: state,
      lifecycle_changed_by: actor["user_id"],
      lifecycle_changed_at: now,
      lifecycle_reason: reason
    })
  end

  defp build_approval(row, version, decision, reason, actor, now) do
    FleetPlanningPolicyApproval.new(%{
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      fleet_planning_policy_id: row.fleet_planning_policy_id,
      fleet_planning_policy_version: version.version,
      decision: decision,
      content_sha256: version.content_sha256,
      reason: reason,
      actor_user_id: actor["user_id"],
      actor_document: actor,
      decided_at: now
    })
  end

  defp build_version(attrs, organization_id, mission_id, policy_id, version, actor_id, now) do
    FleetPlanningPolicyVersion.new(
      attrs
      |> Map.put(:fleet_planning_policy_version_id, Cadence.Ids.new("fleet_policy_version"))
      |> Map.put(:fleet_planning_policy_id, policy_id)
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:mission_id, mission_id)
      |> Map.put(:version, version)
      |> Map.put(:content_sha256, nil)
      |> Map.put(:created_by, actor_id)
      |> Map.put(:created_at, now)
    )
  end

  defp merge_content(current, attrs) do
    defaults =
      current
      |> Map.from_struct()
      |> Map.take(@content_fields)

    Enum.reduce(@content_fields, defaults, fn field, merged ->
      case fetch_value(attrs, field) do
        {:ok, value} -> Map.put(merged, field, value)
        :error -> merged
      end
    end)
  end

  defp validate_document_size(version) do
    size =
      version
      |> FleetPlanningPolicyVersion.content_document()
      |> :erlang.term_to_binary([:deterministic])
      |> byte_size()

    if size <= @document_limit,
      do: :ok,
      else: {:error, :fleet_planning_policy_document_too_large}
  end

  defp update_projection(row, attrs),
    do: row |> FleetPlanningPolicyRow.projection_changeset(attrs) |> Repo.update()

  defp lock_policy(organization_id, mission_id, policy_id) do
    case FleetPlanningPolicyRow
         |> where(
           [policy],
           policy.organization_id == ^organization_id and policy.mission_id == ^mission_id and
             policy.fleet_planning_policy_id == ^policy_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :fleet_planning_policy_not_found}
      row -> {:ok, row}
    end
  end

  defp fetch_version_row(row, version) do
    case Repo.get_by(FleetPlanningPolicyVersionRow,
           organization_id: row.organization_id,
           mission_id: row.mission_id,
           fleet_planning_policy_id: row.fleet_planning_policy_id,
           version: version
         ) do
      nil -> {:error, :fleet_planning_policy_version_not_found}
      version_row -> {:ok, version_row}
    end
  end

  defp expected_version(%FleetPlanningPolicyRow{current_version: version}, version), do: :ok
  defp expected_version(_row, _version), do: {:error, :stale_fleet_planning_policy_version}

  defp exact_hash(%FleetPlanningPolicyVersionRow{content_sha256: hash}, hash), do: :ok
  defp exact_hash(_row, _hash), do: {:error, :stale_fleet_planning_policy_hash}

  defp not_retired(%FleetPlanningPolicyRow{lifecycle_state: "retired"}),
    do: {:error, :fleet_planning_policy_retired}

  defp not_retired(_row), do: :ok

  defp undecided(row, version) do
    if Repo.exists?(
         from(approval in FleetPlanningPolicyApprovalRow,
           where:
             approval.organization_id == ^row.organization_id and
               approval.mission_id == ^row.mission_id and
               approval.fleet_planning_policy_id == ^row.fleet_planning_policy_id and
               approval.fleet_planning_policy_version == ^version
         )
       ),
       do: {:error, :fleet_planning_policy_already_decided},
       else: :ok
  end

  defp require_reason(""), do: {:error, :fleet_planning_policy_decision_reason_required}
  defp require_reason(_reason), do: :ok

  defp authorize_manage(scope) do
    Policy.authorize(scope, :manage_fleet_planning_policy, %{
      organization_id: scope.organization_id
    })
  end

  defp authorize_approve(scope) do
    Policy.authorize(scope, :approve_fleet_planning_policy, %{
      organization_id: scope.organization_id
    })
  end

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: user_id}})
       when is_binary(user_id) and user_id != "",
       do: {:ok, user_id}

  defp actor_id(%Scope{}), do: {:error, :authenticated_user_required}

  defp actor(%Scope{actor_kind: :user, user: user})
       when is_binary(user.user_id) and user.user_id != "" do
    {:ok,
     %{
       "kind" => "user",
       "user_id" => user.user_id,
       "display_name" => user.display_name,
       "email" => user.email
     }}
  end

  defp actor(%Scope{}), do: {:error, :authenticated_user_required}

  defp normalize_create_result({:ok, %{policy: policy, version: version}}) do
    {:ok, FleetPlanningPolicyRow.to_domain(policy),
     FleetPlanningPolicyVersionRow.to_domain(version)}
  end

  defp normalize_create_result({:error, _operation, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_create_result({:error, _operation, reason, _changes}), do: {:error, reason}

  defp normalize_version_result({:ok, {policy, version}}), do: {:ok, policy, version}
  defp normalize_version_result({:error, reason}), do: {:error, reason}

  defp normalize_decision_result({:ok, {policy, version, approval}}),
    do: {:ok, policy, version, approval}

  defp normalize_decision_result({:error, reason}), do: {:error, reason}
  defp normalize_single_result({:ok, policy}), do: {:ok, policy}
  defp normalize_single_result({:error, reason}), do: {:error, reason}

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp fetch_value(attrs, key) do
    cond do
      Map.has_key?(attrs, key) -> {:ok, Map.fetch!(attrs, key)}
      Map.has_key?(attrs, Atom.to_string(key)) -> {:ok, Map.fetch!(attrs, Atom.to_string(key))}
      true -> :error
    end
  end
end
