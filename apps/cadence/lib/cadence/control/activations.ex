defmodule Cadence.Control.Activations do
  @moduledoc """
  Control-plane executor for binding-set activation generations.

  This boundary resolves one immutable governed binding set, records the next
  operational generation, and hands the complete receiver-owned specification
  to the data plane.
  """

  alias Cadence.Activations
  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Activations.SpacecraftConfiguration, as: ConfigurationActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.Activations.{ActivationExecution, ActivationExecutionRow, ExecutionLock}
  alias Cadence.Control.Activations.Resume
  alias Cadence.Control.Activations.Review
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Governance
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Management.Activations.ApprovedActivation
  alias Cadence.Repo
  alias Cadence.Runtime.MissionRuntimeSpec

  @spec execute(ApprovedActivation.t(), keyword()) ::
          {:ok, ActivationExecution.t()} | {:error, term()}
  def execute(%ApprovedActivation{} = approved_activation, opts \\ []) when is_list(opts) do
    approved_activation.activation_request_id
    |> ExecutionLock.run(fn -> execute_locked(approved_activation, opts) end)
    |> settle(opts)
  rescue
    # No connection to run on, or the database dropped before the execution was recorded.
    _exception in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :activation_execution_interrupted}
  end

  @doc """
  Resumes an approved activation whose apply failed or stalled midway (L10): the approver's
  `Retry apply`. See `Cadence.Control.Activations.Resume`.
  """
  def resume(%Scope{} = scope, mission_id, request_id, opts \\ []),
    do: Resume.run(scope, mission_id, request_id, opts)

  defp execute_locked(approved_activation, opts) do
    # A resume records itself here, once it holds the lock (Resume's audit).
    :ok = Keyword.get(opts, :on_locked, fn -> :ok end).()

    with {:ok, execution_row, already_succeeded?} <-
           begin_execution(approved_activation, opts, now(opts)) do
      if already_succeeded? do
        {:ok, ActivationExecutionRow.to_domain(execution_row)}
      else
        execute_and_record(execution_row, approved_activation, opts)
      end
    end
  end

  # Recorded after the lock's connection is given back: it may be the one that dropped.
  defp settle({:interrupted, execution_row, exception}, opts) do
    _ = record_interrupted(execution_row, exception, opts)
    {:error, :activation_execution_interrupted}
  end

  defp settle(result, _opts), do: result

  @doc "Reviews one mission-bound activation request through the host's human approval workflow."
  def review(%Scope{} = scope, mission_id, input), do: Review.decide(scope, mission_id, input)

  @doc """
  Approves `request_id` only if its apply could run (`preflight/2`); otherwise nothing is recorded
  and the request stays pending. Every approve path goes through here (director 11-17). The
  decision's own checks (`ManagementActivations.decidable/3`: pending, authorized, current
  policy, a distinct approver) run first, so their refusals keep their precedence.
  """
  @spec approve(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, term(), term(), term()} | {:error, term()}
  def approve(%Scope{} = scope, request_id, reason, opts \\ []) do
    with :ok <- ManagementActivations.decidable(scope, request_id, :approved),
         {:ok, request} <- ManagementActivations.fetch(scope, request_id),
         :ok <- preflight(request, opts) do
      ManagementActivations.approve(scope, request_id, reason, Keyword.delete(opts, :checks))
    end
  end

  @spec approve_and_execute(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, ActivationExecution.t()} | {:error, term()}
  def approve_and_execute(%Scope{} = current_scope, request_id, reason, opts \\ []) do
    with {:ok, _request, _decision, approved} <- approve(current_scope, request_id, reason, opts) do
      execute(approved, Keyword.delete(opts, :checks))
    end
  end

  @spec fetch_execution(binary()) :: {:ok, ActivationExecution.t()} | {:error, term()}
  def fetch_execution(activation_request_id) when is_binary(activation_request_id) do
    case Repo.get_by(ActivationExecutionRow, activation_request_id: activation_request_id) do
      nil -> {:error, :activation_execution_not_found}
      row -> {:ok, ActivationExecutionRow.to_domain(row)}
    end
  end

  @spec fetch_active_basis(binary(), binary()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def fetch_active_basis(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    Activations.fetch_active_activation(organization_id, mission_id)
  end

  @doc false
  def fetch_active_basis_for_reconciliation(mission_id) when is_binary(mission_id) do
    Activations.fetch_active_activation(mission_id)
  end

  @doc false
  def fetch_active_identity_for_reconciliation(mission_id) when is_binary(mission_id) do
    Activations.fetch_active_identity(mission_id)
  end

  @doc false
  def list_active_bases, do: Activations.list_active_activations()

  defp execute_activation(organization_id, mission_id, %BindingSet{} = binding_set, opts) do
    content_sha256 = MissionRuntimeSpec.content_sha256(binding_set)
    persistence_opts = Keyword.put(opts, :binding_set_content_sha256, content_sha256)

    with {:ok, %BindingSetActivation{} = activation} <-
           record_activation(
             organization_id,
             mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             persistence_opts
           ),
         {:ok, _mission_control} <- ControlMissions.ensure_started(mission_id),
         {:ok, _generation_applied} <-
           MissionRuntimeReconciler.apply_generation(mission_id, activation, binding_set) do
      {:ok, activation}
    end
  end

  defp execute_and_record(execution_row, approved_activation, opts) do
    result =
      with {:ok, %BindingSet{} = binding_set} <-
             Governance.fetch_binding_set(
               approved_activation.organization_id,
               approved_activation.mission_id,
               approved_activation.binding_set_id,
               approved_activation.binding_set_version
             ),
           :ok <-
             deterministic_checks(approved_activation, binding_set, [executing?: true] ++ opts),
           {:ok, %BindingSetActivation{} = activation} <-
             execute_activation(
               approved_activation.organization_id,
               approved_activation.mission_id,
               binding_set,
               opts
               |> Keyword.put(
                 :activation_request_id,
                 approved_activation.activation_request_id
               )
               |> Keyword.put(:metadata, approved_activation.metadata)
             ),
           :ok <-
             TelemetryDecom.activation_applied(
               binding_set,
               applied_metadata(approved_activation.metadata)
             ) do
        complete_execution(execution_row, activation, now(opts))
      end

    case result do
      {:ok, %ActivationExecution{} = execution} ->
        {:ok, execution}

      {:error, reason} ->
        _ = fail_execution(execution_row, reason, now(opts))
        {:error, reason}
    end
  rescue
    # The database dropped mid-way (a connection closed or timed out). Each step is idempotent, so
    # the execution is recorded failed (by `settle/2`) and can be resumed; never left silently in
    # progress.
    exception in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:interrupted, execution_row, exception}
  end

  defp record_interrupted(execution_row, exception, opts) do
    fail_execution(
      execution_row,
      {:activation_execution_interrupted, Exception.message(exception)},
      now(opts)
    )
  rescue
    # Still unreachable: the row stays in progress, which a resume treats as stalled.
    _exception in [DBConnection.ConnectionError, Postgrex.Error] -> :error
  end

  defp begin_execution(approved_activation, opts, started_at) do
    case Repo.get_by(ActivationExecutionRow,
           activation_request_id: approved_activation.activation_request_id
         ) do
      %ActivationExecutionRow{status: :succeeded} = row ->
        {:ok, row, true}

      # Failed or stalled, and this executor holds the lock: start it again.
      %ActivationExecutionRow{} = row ->
        row
        |> ActivationExecutionRow.restart_changeset(executor_actor(opts), started_at)
        |> Repo.update()
        |> case do
          {:ok, row} -> {:ok, row, false}
          {:error, changeset} -> {:error, changeset}
        end

      nil ->
        execution =
          ActivationExecution.new(%{
            activation_request_id: approved_activation.activation_request_id,
            organization_id: approved_activation.organization_id,
            mission_id: approved_activation.mission_id,
            status: :in_progress,
            executor_actor_document: executor_actor(opts),
            activation_id: nil,
            generation: nil,
            binding_set_content_sha256: approved_activation.binding_set_content_sha256,
            error_document: %{},
            started_at: started_at,
            completed_at: nil
          })

        case Repo.insert(ActivationExecutionRow.changeset(execution)) do
          {:ok, row} -> {:ok, row, false}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp complete_execution(execution_row, activation, completed_at) do
    execution_row
    |> ActivationExecutionRow.completion_changeset(%{
      status: :succeeded,
      activation_id: activation.activation_id,
      generation: activation.generation,
      error_document: %{},
      completed_at: completed_at
    })
    |> Repo.update()
    |> case do
      {:ok, row} -> {:ok, ActivationExecutionRow.to_domain(row)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp fail_execution(execution_row, reason, completed_at) do
    execution_row
    |> ActivationExecutionRow.completion_changeset(%{
      status: :failed,
      error_document: %{"reason" => inspect(reason), "code" => error_code(reason)},
      completed_at: completed_at
    })
    |> Repo.update()
  end

  # A stable code for the console (the reason's atom), beside the inspected reason.
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_reason), do: nil

  @doc """
  Whether an approval of `request` could apply: the deterministic checks an apply runs before it
  changes anything (the approved content, the mission-model gate, the policy, a spacecraft review's
  freshness), run BEFORE a decision is recorded (director 11-17). An approval of a request that
  can't apply would record 'approved' for something that never ran. Every approve path calls this
  before deciding; execute runs the SAME list (`deterministic_checks/3`), so the two can't drift.
  Only transient failures (the runtime apply, a lost connection) are left for after the decision,
  where Retry apply handles them. `opts[:checks]` replaces the list (tests).

  It runs OUTSIDE the decision's lock (the configuration admission takes the configuration lock,
  which the host decide takes before the request row), so a change in the small window between
  the preflight and the record (a model un-approved just then) still records 'approved' and fails
  at execute, as before this check. For a reviewed-spacecraft request the admission also locks
  each reviewed craft briefly, so a large review's approval can contend with a concurrent
  change-set apply.
  """
  @spec preflight(map(), keyword()) :: :ok | {:error, term()}
  def preflight(request, opts \\ []) do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(
             request.organization_id,
             request.mission_id,
             request.binding_set_id,
             request.binding_set_version
           ) do
      deterministic_checks(request, binding_set, opts)
    end
  end

  @doc "The deterministic checks, in order: what both an apply and an approval's preflight run."
  def deterministic_check_list,
    do: [
      &exact_approved_content/2,
      &model_gate/2,
      &__MODULE__.policy_current/2,
      &__MODULE__.configuration_current/2
    ]

  # The policy and the configuration admission: an apply runs them inside the activation's own
  # transaction, under its locks and only for a not-yet-recorded activation (Activations), so
  # execute's pre-check skips them; the approval preflight runs the whole list.
  @admitted_in_transaction [&__MODULE__.policy_current/2, &__MODULE__.configuration_current/2]

  defp deterministic_checks(activation, binding_set, opts) do
    opts
    |> Keyword.get(:checks, deterministic_check_list())
    |> Enum.reject(&(Keyword.get(opts, :executing?, false) and &1 in @admitted_in_transaction))
    |> Enum.reduce_while(:ok, fn check, :ok ->
      case check.(activation, binding_set) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp model_gate(activation, binding_set),
    do:
      MissionModelPromotion.validate_activation_metadata(
        activation.organization_id,
        activation.mission_id,
        binding_set,
        activation.metadata
      )

  @doc false
  def policy_current(activation, _binding_set),
    do:
      ActivationPolicy.validate(
        activation.organization_id,
        activation.mission_id,
        activation.policy_document
      )

  # A spacecraft review or change-set fleet still matches what's active (read-only, under the
  # configuration lock; the activation's own transaction runs it again).
  @doc false
  def configuration_current(activation, _binding_set) do
    activation
    |> Map.take([
      :organization_id,
      :mission_id,
      :binding_set_id,
      :binding_set_version,
      :binding_set_content_sha256,
      :metadata,
      :activation_request_id
    ])
    |> ConfigurationActivation.admit()
    |> case do
      {:ok, _admitted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp exact_approved_content(approved_activation, binding_set) do
    if BindingSet.content_sha256(binding_set) == approved_activation.binding_set_content_sha256 do
      :ok
    else
      {:error, :approved_activation_content_mismatch}
    end
  end

  defp executor_actor(opts) do
    Keyword.get(opts, :executor_actor_document, %{
      "kind" => "service",
      "id" => "cadence:activation_executor",
      "display_name" => "Cadence Activation Executor"
    })
  end

  defp now(opts) do
    datetime = Keyword.get(opts, :now, DateTime.utc_now())
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end

  defp record_activation(nil, mission_id, binding_set_id, version, opts) do
    Activations.record_binding_set_activation(mission_id, binding_set_id, version, opts)
  end

  defp record_activation(organization_id, mission_id, binding_set_id, version, opts) do
    Activations.record_binding_set_activation(
      organization_id,
      mission_id,
      binding_set_id,
      version,
      opts
    )
  end

  # TelemetryDecom runs in the data plane and can't read stored fleets; hand it the entries.
  defp applied_metadata(%{"spacecraft_configuration_version" => 2} = metadata) do
    case FleetSnapshot.entries(metadata) do
      {:ok, entries} ->
        %{"spacecraft_configuration_version" => 1, "spacecraft_configurations" => entries}

      {:error, _reason} ->
        metadata
    end
  end

  defp applied_metadata(metadata), do: metadata
end
