defmodule Cadence.Control.Activations do
  @moduledoc """
  Control-plane executor for binding-set activation generations.

  This boundary resolves one immutable governed binding set, records the next
  operational generation, and hands the complete receiver-owned specification
  to the data plane.
  """

  alias Cadence.Activations
  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Control.Activations.{ActivationExecution, ActivationExecutionRow}
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Governance
  alias Cadence.Management.Activations.ApprovedActivation
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.Runtime.MissionRuntimeSpec

  @spec execute(ApprovedActivation.t(), keyword()) ::
          {:ok, ActivationExecution.t()} | {:error, term()}
  def execute(%ApprovedActivation{} = approved_activation, opts \\ []) when is_list(opts) do
    started_at = now(opts)

    with {:ok, execution_row, already_succeeded?} <-
           begin_execution(approved_activation, opts, started_at) do
      if already_succeeded? do
        {:ok, ActivationExecutionRow.to_domain(execution_row)}
      else
        execute_and_record(execution_row, approved_activation, opts)
      end
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
  def list_active_bases, do: Activations.list_active_activations()

  @spec activate_binding_set(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def activate_binding_set(organization_id, mission_id, binding_set_id, version, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 and is_list(opts) do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(organization_id, mission_id, binding_set_id, version) do
      execute_activation(organization_id, mission_id, binding_set, opts)
    end
  end

  @spec activate_binding_set(binary(), binary(), pos_integer(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def activate_binding_set(mission_id, binding_set_id, version, opts \\ [])
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    with {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(mission_id, binding_set_id, version) do
      execute_activation(binding_set.organization_id, mission_id, binding_set, opts)
    end
  end

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
           :ok <- exact_approved_content(approved_activation, binding_set),
           {:ok, %BindingSetActivation{} = activation} <-
             execute_activation(
               approved_activation.organization_id,
               approved_activation.mission_id,
               binding_set,
               Keyword.put(
                 opts,
                 :activation_request_id,
                 approved_activation.activation_request_id
               )
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
  end

  defp begin_execution(approved_activation, opts, started_at) do
    case Repo.get_by(ActivationExecutionRow,
           activation_request_id: approved_activation.activation_request_id
         ) do
      %ActivationExecutionRow{status: :succeeded} = row ->
        {:ok, row, true}

      %ActivationExecutionRow{} = row ->
        {:ok, row, false}

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
      error_document: %{"reason" => inspect(reason)},
      completed_at: completed_at
    })
    |> Repo.update()
  end

  defp exact_approved_content(approved_activation, binding_set) do
    if ContentHash.term_sha256(binding_set) == approved_activation.binding_set_content_sha256 do
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
end
