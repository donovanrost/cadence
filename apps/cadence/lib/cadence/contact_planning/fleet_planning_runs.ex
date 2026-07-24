defmodule Cadence.ContactPlanning.FleetPlanningRuns do
  @moduledoc "Authorized durable lifecycle and evidence boundary for fleet planning orchestration."

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    FleetPlanningDecision,
    FleetPlanningPolicies,
    FleetPlanningRun,
    FleetPlanningRunRequirementRef
  }

  alias Cadence.Management.Contacts.Store.{
    FleetPlanningDecisionRow,
    FleetPlanningRunRequirementRefRow,
    FleetPlanningRunRow
  }

  alias Cadence.Repo

  @algorithm_key "deterministic_bounded_greedy"
  @algorithm_version 1
  @maximum_requirements 10_000
  @document_limit 256 * 1_024

  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, FleetPlanningRun.t(), [FleetPlanningRunRequirementRef.t()]} | {:error, term()}
  def create(%Scope{} = scope, mission_id, attrs, _opts \\ [])
      when is_binary(mission_id) and is_map(attrs) do
    with :ok <- authorize_member(scope, mission_id),
         {:ok, _policy, policy_version} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         {:ok, horizon_start} <- datetime(value(attrs, :horizon_start)),
         {:ok, horizon_end} <- datetime(value(attrs, :horizon_end)),
         :ok <- validate_horizon(horizon_start, horizon_end, policy_version),
         {:ok, requirements} <-
           select_requirements(
             scope.organization_id,
             mission_id,
             horizon_start,
             horizon_end,
             attrs
           ),
         :ok <- require_requirements(requirements),
         {:ok, actor} <- actor(scope),
         {:ok, run} <-
           build_run(
             scope.organization_id,
             mission_id,
             policy_version,
             requirements,
             horizon_start,
             horizon_end,
             actor,
             attrs
           ) do
      persist_run(run, requirements)
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, FleetPlanningRun.t()} | {:error, term()}
  def fetch(organization_id, mission_id, run_id) do
    case Repo.get_by(FleetPlanningRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           fleet_planning_run_id: run_id
         ) do
      nil -> {:error, :fleet_planning_run_not_found}
      row -> {:ok, FleetPlanningRunRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [FleetPlanningRun.t()]
  def list(organization_id, mission_id, opts \\ []) do
    FleetPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id
    )
    |> maybe_filter_state(opts[:lifecycle_state])
    |> order_by([run], desc: run.inserted_at, desc: run.fleet_planning_run_id)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
    |> Enum.map(&FleetPlanningRunRow.to_domain/1)
  end

  @spec list_requirement_refs(binary(), binary(), binary()) ::
          [FleetPlanningRunRequirementRef.t()]
  def list_requirement_refs(organization_id, mission_id, run_id) do
    FleetPlanningRunRequirementRefRow
    |> where(
      [ref],
      ref.organization_id == ^organization_id and ref.mission_id == ^mission_id and
        ref.fleet_planning_run_id == ^run_id
    )
    |> order_by([ref], asc: ref.contact_requirement_id, asc: ref.contact_requirement_version)
    |> Repo.all()
    |> Enum.map(&FleetPlanningRunRequirementRefRow.to_domain/1)
  end

  @spec list_decisions(binary(), binary(), binary()) :: [FleetPlanningDecision.t()]
  def list_decisions(organization_id, mission_id, run_id) do
    FleetPlanningDecisionRow
    |> where(
      [decision],
      decision.organization_id == ^organization_id and decision.mission_id == ^mission_id and
        decision.fleet_planning_run_id == ^run_id
    )
    |> order_by([decision],
      asc_nulls_last: decision.rank,
      desc: decision.score,
      asc: decision.contact_opportunity_snapshot_id
    )
    |> Repo.all()
    |> Enum.map(&FleetPlanningDecisionRow.to_domain/1)
  end

  @spec advance_phase(
          Scope.t(),
          binary(),
          binary(),
          atom(),
          atom(),
          map(),
          keyword()
        ) :: {:ok, FleetPlanningRun.t()} | {:error, term()}
  def advance_phase(
        %Scope{} = scope,
        mission_id,
        run_id,
        expected_phase,
        next_phase,
        attrs \\ %{},
        opts \\ []
      )
      when is_atom(expected_phase) and is_atom(next_phase) and is_map(attrs) do
    now = now(opts)

    with :ok <- authorize_member(scope, mission_id),
         :ok <- allowed_phase_transition(expected_phase, next_phase) do
      advance_transaction(
        scope.organization_id,
        mission_id,
        run_id,
        expected_phase,
        next_phase,
        attrs,
        now
      )
    end
  end

  @spec cancel(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, FleetPlanningRun.t()} | {:error, term()}
  def cancel(%Scope{} = scope, mission_id, run_id, reason, opts \\ []) do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_member(scope, mission_id),
         :ok <- require_reason(reason) do
      cancel_transaction(scope.organization_id, mission_id, run_id, reason, now)
    end
  end

  @spec fail(Scope.t(), binary(), binary(), atom(), map(), keyword()) ::
          {:ok, FleetPlanningRun.t()} | {:error, term()}
  def fail(
        %Scope{} = scope,
        mission_id,
        run_id,
        expected_phase,
        failure_document,
        opts \\ []
      )
      when is_atom(expected_phase) and is_map(failure_document) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_member(scope, mission_id),
         :ok <- bounded_document(failure_document, :fleet_planning_run_failure_too_large) do
      fail_transaction(
        scope.organization_id,
        mission_id,
        run_id,
        expected_phase,
        failure_document,
        now
      )
    end
  end

  @spec update_requirement_progress(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          atom(),
          atom(),
          map()
        ) :: {:ok, FleetPlanningRunRequirementRef.t()} | {:error, term()}
  def update_requirement_progress(
        %Scope{} = scope,
        mission_id,
        run_id,
        requirement_id,
        input_state,
        result_state,
        attrs \\ %{}
      )
      when is_atom(input_state) and is_atom(result_state) and is_map(attrs) do
    with :ok <- authorize_member(scope, mission_id) do
      case Repo.get_by(FleetPlanningRunRequirementRefRow,
             organization_id: scope.organization_id,
             mission_id: mission_id,
             fleet_planning_run_id: run_id,
             contact_requirement_id: requirement_id
           ) do
        nil ->
          {:error, :fleet_planning_run_requirement_not_found}

        row ->
          persist_requirement_progress(row, input_state, result_state, attrs)
      end
    end
  end

  @spec persist_decisions(Scope.t(), binary(), binary(), [map()]) ::
          {:ok, [FleetPlanningDecision.t()]} | {:error, term()}
  def persist_decisions(%Scope{} = scope, mission_id, run_id, decisions)
      when is_list(decisions) do
    with :ok <- authorize_member(scope, mission_id),
         {:ok, run} <- fetch(scope.organization_id, mission_id, run_id),
         :ok <- optimizing_run(run),
         {:ok, normalized} <- build_decisions(run, decisions) do
      Repo.transaction(fn -> replace_decisions(run_id, normalized) end)
      |> normalize_list_result()
    end
  end

  defp persist_run(run, requirements) do
    Repo.transaction(fn ->
      with {:ok, run_row} <- Repo.insert(FleetPlanningRunRow.changeset(run)),
           {:ok, refs} <- insert_requirement_refs(run, requirements) do
        {FleetPlanningRunRow.to_domain(run_row), refs}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {persisted_run, refs}} -> {:ok, persisted_run, refs}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_requirement_refs(run, requirements) do
    requirements
    |> Enum.map(fn {_requirement, version} ->
      FleetPlanningRunRequirementRef.new(%{
        fleet_planning_run_id: run.fleet_planning_run_id,
        organization_id: run.organization_id,
        mission_id: run.mission_id,
        contact_requirement_id: version.contact_requirement_id,
        contact_requirement_version: version.version,
        input_state: :pending,
        result_state: :pending,
        explanation_document: %{}
      })
    end)
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, inserted} ->
      case Repo.insert(FleetPlanningRunRequirementRefRow.changeset(ref)) do
        {:ok, row} ->
          {:cont, {:ok, [FleetPlanningRunRequirementRefRow.to_domain(row) | inserted]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, refs} -> {:ok, Enum.reverse(refs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_run(
         organization_id,
         mission_id,
         policy,
         requirements,
         horizon_start,
         horizon_end,
         actor,
         attrs
       ) do
    refs =
      Enum.map(requirements, fn {_requirement, version} ->
        %{
          "contact_requirement_id" => version.contact_requirement_id,
          "contact_requirement_version" => version.version,
          "content_sha256" => version.content_sha256
        }
      end)

    run =
      FleetPlanningRun.new(%{
        fleet_planning_run_id:
          value(attrs, :fleet_planning_run_id, Cadence.Ids.new("fleet_planning_run")),
        organization_id: organization_id,
        mission_id: mission_id,
        lifecycle_state: :queued,
        phase: :queued,
        trigger_kind: value(attrs, :trigger_kind, :manual),
        fleet_planning_policy_id: policy.fleet_planning_policy_id,
        fleet_planning_policy_version: policy.version,
        algorithm_key: @algorithm_key,
        algorithm_version: @algorithm_version,
        horizon_start: horizon_start,
        horizon_end: horizon_end,
        source_fleet_planning_run_id: value(attrs, :source_fleet_planning_run_id, nil),
        source_contact_plan_id: value(attrs, :source_contact_plan_id, nil),
        source_contact_plan_version: value(attrs, :source_contact_plan_version, nil),
        input_document: %{
          "requirements" => refs,
          "requirement_count" => length(refs),
          "policy_content_sha256" => policy.content_sha256,
          "template_materialization" => value(attrs, :template_materialization_document, %{}),
          "repair" => value(attrs, :repair_input_document, %{})
        },
        progress_document: initial_progress(length(refs)),
        result_summary_document: %{},
        failure_document: %{},
        trigger_actor_document: actor,
        triggered_by: actor["id"],
        started_at: nil,
        completed_at: nil
      })

    if document_size(run.input_document) <= @document_limit,
      do: {:ok, run},
      else: {:error, :fleet_planning_run_input_too_large}
  rescue
    error in ArgumentError -> {:error, {:invalid_fleet_planning_run, error.message}}
  end

  defp select_requirements(organization_id, mission_id, horizon_start, horizon_end, attrs) do
    case value(attrs, :requirement_refs, nil) do
      nil ->
        select_active_requirements(organization_id, mission_id, horizon_start, horizon_end)

      refs when is_list(refs) ->
        select_explicit_requirements(organization_id, mission_id, refs)

      _value ->
        {:error, :fleet_planning_run_requirement_refs_invalid}
    end
  end

  defp select_active_requirements(organization_id, mission_id, horizon_start, horizon_end) do
    requirements =
      organization_id
      |> ContactRequirements.list(mission_id, lifecycle_state: :active)
      |> Enum.filter(fn {_requirement, version} ->
        DateTime.before?(version.earliest_start, horizon_end) and
          DateTime.after?(version.latest_end, horizon_start)
      end)
      |> Enum.take(@maximum_requirements)

    {:ok, requirements}
  end

  defp select_explicit_requirements(organization_id, mission_id, refs) do
    refs
    |> Enum.uniq_by(fn ref ->
      {value(ref, :contact_requirement_id, value(ref, :id, nil)), value(ref, :version, nil)}
    end)
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, selected} ->
      case fetch_current_requirement(organization_id, mission_id, ref) do
        {:ok, requirement} -> {:cont, {:ok, [requirement | selected]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> normalize_selected_requirements()
  end

  defp normalize_selected_requirements({:ok, selected}) do
    selected =
      selected
      |> Enum.reverse()
      |> Enum.sort_by(fn {_requirement, version} ->
        {version.latest_end, version.contact_requirement_id}
      end)

    if length(selected) <= @maximum_requirements,
      do: {:ok, selected},
      else: {:error, :fleet_planning_run_requirement_limit_exceeded}
  end

  defp normalize_selected_requirements({:error, reason}), do: {:error, reason}

  defp fetch_current_requirement(organization_id, mission_id, ref) when is_map(ref) do
    requirement_id =
      value(ref, :contact_requirement_id, value(ref, :id, nil))

    expected_version = value(ref, :version, nil)

    case ContactRequirements.fetch(organization_id, mission_id, requirement_id) do
      {:ok, %{lifecycle_state: :active, current_version: ^expected_version} = requirement,
       version} ->
        {:ok, {requirement, version}}

      {:ok, %{lifecycle_state: state}, _version} when state != :active ->
        {:error, :fleet_planning_requirement_not_active}

      {:ok, _requirement, _version} ->
        {:error, :fleet_planning_requirement_version_changed}

      {:error, _reason} ->
        {:error, :fleet_planning_requirement_not_found}
    end
  end

  defp fetch_current_requirement(_organization_id, _mission_id, _ref),
    do: {:error, :fleet_planning_run_requirement_refs_invalid}

  defp validate_horizon(start_at, end_at, policy) do
    duration = DateTime.diff(end_at, start_at, :second)

    cond do
      duration <= 0 ->
        {:error, :fleet_planning_horizon_invalid}

      duration > policy.horizon_document["max_horizon_seconds"] ->
        {:error, :fleet_planning_horizon_exceeds_policy}

      true ->
        :ok
    end
  end

  defp require_requirements([]), do: {:error, :fleet_planning_run_has_no_requirements}
  defp require_requirements(_requirements), do: :ok

  defp persist_requirement_progress(row, input_state, result_state, attrs) do
    row
    |> FleetPlanningRunRequirementRefRow.progress_changeset(%{
      contact_planning_run_id:
        value(attrs, :contact_planning_run_id, row.contact_planning_run_id),
      input_state: Atom.to_string(input_state),
      result_state: Atom.to_string(result_state),
      explanation_document: value(attrs, :explanation_document, row.explanation_document)
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, FleetPlanningRunRequirementRefRow.to_domain(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_decisions(run_id, decisions) do
    FleetPlanningDecisionRow
    |> where([decision], decision.fleet_planning_run_id == ^run_id)
    |> Repo.delete_all()

    Enum.map(decisions, &insert_decision!/1)
  end

  defp insert_decision!(decision) do
    case Repo.insert(FleetPlanningDecisionRow.changeset(decision)) do
      {:ok, row} -> FleetPlanningDecisionRow.to_domain(row)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp advance_transaction(
         organization_id,
         mission_id,
         run_id,
         expected_phase,
         next_phase,
         attrs,
         now
       ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_run(organization_id, mission_id, run_id),
           {:ok, result} <- advance_locked(row, expected_phase, next_phase, attrs, now) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_single_result()
  end

  defp cancel_transaction(organization_id, mission_id, run_id, reason, now) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_run(organization_id, mission_id, run_id),
           :ok <- cancelable(row),
           {:ok, updated} <-
             update_run(row, %{
               lifecycle_state: "canceled",
               phase: "finished",
               progress_document: row.progress_document,
               result_summary_document: row.result_summary_document,
               failure_document: %{"code" => "operator_canceled", "reason" => reason},
               completed_at: now
             }) do
        FleetPlanningRunRow.to_domain(updated)
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> normalize_single_result()
  end

  defp fail_transaction(
         organization_id,
         mission_id,
         run_id,
         expected_phase,
         failure_document,
         now
       ) do
    Repo.transaction(fn ->
      with {:ok, row} <- lock_run(organization_id, mission_id, run_id),
           {:ok, failed} <- fail_locked(row, expected_phase, failure_document, now) do
        failed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_single_result()
  end

  defp advance_locked(row, expected, next, attrs, now) do
    cond do
      row.phase == Atom.to_string(next) ->
        {:ok, FleetPlanningRunRow.to_domain(row)}

      row.phase != Atom.to_string(expected) ->
        {:error, :stale_fleet_planning_run_phase}

      row.lifecycle_state in ["completed", "partial", "failed", "canceled"] ->
        {:error, :fleet_planning_run_terminal}

      true ->
        lifecycle_state = phase_lifecycle(next, attrs)

        row
        |> update_run(%{
          lifecycle_state: Atom.to_string(lifecycle_state),
          phase: Atom.to_string(next),
          progress_document: value(attrs, :progress_document, row.progress_document),
          result_summary_document:
            value(attrs, :result_summary_document, row.result_summary_document),
          failure_document: value(attrs, :failure_document, row.failure_document),
          candidate_contact_plan_id:
            value(attrs, :candidate_contact_plan_id, row.candidate_contact_plan_id),
          candidate_contact_plan_version:
            value(attrs, :candidate_contact_plan_version, row.candidate_contact_plan_version),
          started_at: row.started_at || now,
          completed_at: if(next == :finished, do: now, else: row.completed_at)
        })
        |> case do
          {:ok, updated} -> {:ok, FleetPlanningRunRow.to_domain(updated)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp phase_lifecycle(:finished, attrs) do
    case value(attrs, :outcome, :completed) do
      outcome when outcome in [:completed, :partial, :failed] -> outcome
      _outcome -> :failed
    end
  end

  defp phase_lifecycle(_phase, _attrs), do: :running

  defp fail_locked(%FleetPlanningRunRow{lifecycle_state: "failed"} = row, _phase, _failure, _now),
    do: {:ok, FleetPlanningRunRow.to_domain(row)}

  defp fail_locked(
         %FleetPlanningRunRow{lifecycle_state: state},
         _phase,
         _failure,
         _now
       )
       when state in ["completed", "partial", "canceled"],
       do: {:error, :fleet_planning_run_terminal}

  defp fail_locked(row, expected_phase, failure_document, now) do
    if row.phase == Atom.to_string(expected_phase) do
      row
      |> update_run(%{
        lifecycle_state: "failed",
        phase: "finished",
        progress_document: row.progress_document,
        result_summary_document: row.result_summary_document,
        failure_document: failure_document,
        completed_at: now
      })
      |> case do
        {:ok, updated} -> {:ok, FleetPlanningRunRow.to_domain(updated)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :stale_fleet_planning_run_phase}
    end
  end

  defp allowed_phase_transition(:queued, :materializing), do: :ok
  defp allowed_phase_transition(:materializing, :searching), do: :ok
  defp allowed_phase_transition(:searching, :optimizing), do: :ok
  defp allowed_phase_transition(:optimizing, :materializing_plan), do: :ok
  defp allowed_phase_transition(:materializing_plan, :finished), do: :ok
  defp allowed_phase_transition(_expected, _next), do: {:error, :invalid_fleet_planning_phase}

  defp build_decisions(run, decisions) do
    decisions
    |> Enum.map(fn attrs ->
      FleetPlanningDecision.new(
        attrs
        |> Map.put(:fleet_planning_run_id, run.fleet_planning_run_id)
        |> Map.put(:organization_id, run.organization_id)
        |> Map.put(:mission_id, run.mission_id)
      )
    end)
    |> then(&{:ok, &1})
  rescue
    error in ArgumentError -> {:error, {:invalid_fleet_planning_decision, error.message}}
  end

  defp optimizing_run(%FleetPlanningRun{phase: :optimizing}), do: :ok
  defp optimizing_run(_run), do: {:error, :fleet_planning_run_not_optimizing}

  defp cancelable(%FleetPlanningRunRow{lifecycle_state: state})
       when state in ["queued", "running"],
       do: :ok

  defp cancelable(_row), do: {:error, :fleet_planning_run_terminal}

  defp update_run(row, attrs),
    do: row |> FleetPlanningRunRow.projection_changeset(attrs) |> Repo.update()

  defp lock_run(organization_id, mission_id, run_id) do
    case FleetPlanningRunRow
         |> where(
           [run],
           run.organization_id == ^organization_id and run.mission_id == ^mission_id and
             run.fleet_planning_run_id == ^run_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :fleet_planning_run_not_found}
      row -> {:ok, row}
    end
  end

  defp initial_progress(requirement_count) do
    %{
      "requirements_total" => requirement_count,
      "requirements_searched" => 0,
      "requirements_failed" => 0,
      "snapshots_considered" => 0,
      "snapshots_selected" => 0
    }
  end

  defp actor(%Scope{actor_kind: :user, user: user}) do
    {:ok,
     %{
       "kind" => "user",
       "id" => user.user_id,
       "display_name" => user.display_name,
       "email" => user.email
     }}
  end

  defp actor(%Scope{actor_kind: :service, service_identity: identity}) do
    {:ok,
     %{
       "kind" => "service",
       "id" => identity.service_identity_id,
       "display_name" => identity.display_name
     }}
  end

  defp actor(%Scope{}), do: {:error, :authenticated_actor_required}

  defp authorize_member(scope, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp maybe_filter_state(query, nil), do: query

  defp maybe_filter_state(query, state)
       when state in [:queued, :running, :completed, :partial, :failed, :canceled],
       do: where(query, [run], run.lifecycle_state == ^Atom.to_string(state))

  defp require_reason(""), do: {:error, :fleet_planning_run_cancel_reason_required}
  defp require_reason(_reason), do: :ok

  defp datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :microsecond)}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, DateTime.truncate(parsed, :microsecond)}
      _other -> {:error, :fleet_planning_horizon_invalid}
    end
  end

  defp datetime(_value), do: {:error, :fleet_planning_horizon_invalid}

  defp normalize_single_result({:ok, run}), do: {:ok, run}
  defp normalize_single_result({:error, reason}), do: {:error, reason}
  defp normalize_list_result({:ok, items}), do: {:ok, items}
  defp normalize_list_result({:error, reason}), do: {:error, reason}

  defp document_size(document),
    do: document |> :erlang.term_to_binary([:deterministic]) |> byte_size()

  defp bounded_document(document, error) do
    if document_size(document) <= @document_limit, do: :ok, else: {:error, error}
  end

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
