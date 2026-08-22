defmodule Cadence.ContactPlanning.FleetAutomationActions do
  @moduledoc "Idempotent durable checkpoints for unattended fleet workflow actions."

  import Ecto.Query

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    AutomationGrant,
    ContentHash,
    FleetAutomationAction
  }

  alias Cadence.Control.Contacts.Store.FleetAutomationActionRow
  alias Cadence.Repo

  @document_limit 128 * 1_024

  @spec begin_action(
          Scope.t(),
          AutomationGrant.t(),
          binary(),
          atom(),
          map(),
          map(),
          keyword()
        ) ::
          {:ok, :created | :resume | :complete, FleetAutomationAction.t()}
          | {:error, term()}
  def begin_action(
        %Scope{} = scope,
        %AutomationGrant{} = grant,
        fleet_run_id,
        action,
        evidence,
        plan_ref \\ %{},
        opts \\ []
      )
      when is_binary(fleet_run_id) and is_atom(action) and is_map(evidence) and
             is_map(plan_ref) and is_list(opts) do
    now = now(opts)

    with :ok <- exact_actor(scope, grant),
         :ok <- bounded(evidence),
         {:ok, candidate} <-
           build_action(scope, grant, fleet_run_id, action, evidence, plan_ref, now) do
      begin_transaction(candidate, now)
    end
  end

  @spec complete(
          Scope.t(),
          binary(),
          :succeeded | :failed | :skipped,
          map(),
          map(),
          keyword()
        ) :: {:ok, FleetAutomationAction.t()} | {:error, term()}
  def complete(scope, action_id, outcome, result_document, error_document \\ %{}, opts \\ [])

  def complete(
        %Scope{} = scope,
        action_id,
        outcome,
        result_document,
        error_document,
        opts
      )
      when is_binary(action_id) and outcome in [:succeeded, :failed, :skipped] and
             is_map(result_document) and is_map(error_document) and is_list(opts) do
    now = now(opts)

    with :ok <- bounded(result_document),
         :ok <- bounded(error_document) do
      complete_transaction(scope, action_id, outcome, result_document, error_document, now)
    end
  end

  @spec list(binary(), binary(), binary()) :: [FleetAutomationAction.t()]
  def list(organization_id, mission_id, fleet_run_id) do
    FleetAutomationActionRow
    |> where(
      [action],
      action.organization_id == ^organization_id and action.mission_id == ^mission_id and
        action.fleet_planning_run_id == ^fleet_run_id
    )
    |> order_by([action], asc: action.inserted_at, asc: action.action)
    |> Repo.all()
    |> Enum.map(&FleetAutomationActionRow.to_domain/1)
  end

  defp build_action(scope, grant, fleet_run_id, action, evidence, plan_ref, now) do
    plan_id = value(plan_ref, :contact_plan_id)
    plan_version = value(plan_ref, :contact_plan_version)

    idempotency_key =
      ContentHash.sha256(%{
        "automation_grant_id" => grant.automation_grant_id,
        "fleet_planning_run_id" => fleet_run_id,
        "contact_plan_id" => plan_id,
        "contact_plan_version" => plan_version,
        "action" => Atom.to_string(action)
      })

    {:ok,
     FleetAutomationAction.new(%{
       idempotency_key: "cadence:fleet-automation:#{idempotency_key}",
       organization_id: grant.organization_id,
       mission_id: grant.mission_id,
       automation_grant_id: grant.automation_grant_id,
       automation_grant_content_sha256: grant.content_sha256,
       service_identity_id: scope.service_identity.service_identity_id,
       fleet_planning_run_id: fleet_run_id,
       contact_plan_id: plan_id,
       contact_plan_version: plan_version,
       action: action,
       lifecycle_state: :running,
       attempt_count: 1,
       evidence_document: evidence,
       result_document: %{},
       error_document: %{},
       started_at: now
     })}
  rescue
    error in ArgumentError -> {:error, {:invalid_fleet_automation_action, error.message}}
  end

  defp exact_actor(
         %Scope{
           actor_kind: :service,
           organization_id: organization_id,
           mission_id: mission_id,
           service_identity: %{service_identity_id: service_identity_id}
         },
         %AutomationGrant{
           organization_id: organization_id,
           mission_id: mission_id,
           service_identity_id: service_identity_id
         }
       ),
       do: :ok

  defp exact_actor(%Scope{}, %AutomationGrant{}),
    do: {:error, :fleet_automation_action_actor_mismatch}

  defp row_actor(
         %FleetAutomationActionRow{
           organization_id: organization_id,
           mission_id: mission_id,
           service_identity_id: service_identity_id
         },
         %Scope{
           actor_kind: :service,
           organization_id: organization_id,
           mission_id: mission_id,
           service_identity: %{service_identity_id: service_identity_id}
         }
       ),
       do: :ok

  defp row_actor(_row, _scope), do: {:error, :fleet_automation_action_actor_mismatch}

  defp lock_by_key(key) do
    FleetAutomationActionRow
    |> where([action], action.idempotency_key == ^key)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp begin_transaction(candidate, now) do
    Repo.transaction(fn ->
      candidate.idempotency_key
      |> lock_by_key()
      |> resolve_begin(candidate, now)
    end)
    |> case do
      {:ok, {status, persisted}} -> {:ok, status, persisted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_begin(nil, candidate, now), do: insert_or_resume(candidate, now)

  defp resolve_begin(%FleetAutomationActionRow{lifecycle_state: state} = row, _candidate, _now)
       when state in ["succeeded", "skipped"],
       do: {:complete, FleetAutomationActionRow.to_domain(row)}

  defp resolve_begin(
         %FleetAutomationActionRow{lifecycle_state: "failed"} = row,
         _candidate,
         now
       ),
       do: restart(row, now)

  defp resolve_begin(%FleetAutomationActionRow{} = row, _candidate, _now),
    do: {:resume, FleetAutomationActionRow.to_domain(row)}

  defp insert_or_resume(candidate, now) do
    case Repo.insert(FleetAutomationActionRow.changeset(candidate),
           on_conflict: :nothing,
           conflict_target: [:idempotency_key]
         ) do
      {:ok, inserted} ->
        candidate.idempotency_key
        |> lock_by_key()
        |> resolve_inserted_action(candidate, inserted, now)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp resolve_inserted_action(
         %FleetAutomationActionRow{fleet_automation_action_id: id} = row,
         %{fleet_automation_action_id: id},
         _inserted,
         _now
       ),
       do: {:created, FleetAutomationActionRow.to_domain(row)}

  defp resolve_inserted_action(
         %FleetAutomationActionRow{lifecycle_state: state} = row,
         _candidate,
         _inserted,
         _now
       )
       when state in ["succeeded", "skipped"],
       do: {:complete, FleetAutomationActionRow.to_domain(row)}

  defp resolve_inserted_action(
         %FleetAutomationActionRow{lifecycle_state: "failed"} = row,
         _candidate,
         _inserted,
         now
       ),
       do: restart(row, now)

  defp resolve_inserted_action(
         %FleetAutomationActionRow{} = row,
         _candidate,
         _inserted,
         _now
       ),
       do: {:resume, FleetAutomationActionRow.to_domain(row)}

  defp resolve_inserted_action(nil, _candidate, inserted, _now),
    do: Repo.rollback({:fleet_automation_action_insert_not_visible, inserted})

  defp restart(row, now) do
    case row
         |> FleetAutomationActionRow.restart_changeset(now)
         |> Repo.update() do
      {:ok, restarted} -> {:resume, FleetAutomationActionRow.to_domain(restarted)}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_action(action_id) do
    FleetAutomationActionRow
    |> where([action], action.fleet_automation_action_id == ^action_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp complete_transaction(scope, action_id, outcome, result, error, now) do
    Repo.transaction(fn ->
      action_id
      |> lock_action()
      |> complete_locked(scope, outcome, result, error, now)
    end)
    |> case do
      {:ok, completed} -> {:ok, completed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp complete_locked(nil, _scope, _outcome, _result, _error, _now),
    do: Repo.rollback(:fleet_automation_action_not_found)

  defp complete_locked(row, scope, outcome, result, error, now) do
    case row_actor(row, scope) do
      :ok -> complete_state(row, outcome, result, error, now)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp complete_state(
         %FleetAutomationActionRow{lifecycle_state: "running"} = row,
         outcome,
         result,
         error,
         now
       ) do
    row
    |> FleetAutomationActionRow.completion_changeset(%{
      lifecycle_state: Atom.to_string(outcome),
      result_document: result,
      error_document: error,
      completed_at: now
    })
    |> Repo.update()
    |> case do
      {:ok, completed} -> FleetAutomationActionRow.to_domain(completed)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp complete_state(row, outcome, _result, _error, _now) do
    if row.lifecycle_state == Atom.to_string(outcome),
      do: FleetAutomationActionRow.to_domain(row),
      else: Repo.rollback(:fleet_automation_action_already_complete)
  end

  defp bounded(document) do
    if document |> :erlang.term_to_binary([:deterministic]) |> byte_size() <= @document_limit,
      do: :ok,
      else: {:error, :fleet_automation_action_document_too_large}
  end

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
