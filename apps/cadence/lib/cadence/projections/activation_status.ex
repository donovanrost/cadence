defmodule Cadence.Projections.ActivationStatus do
  @moduledoc """
  Read-side view that keeps desired, applied, and observed activation state
  visibly separate.
  """

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Management.Activations.ActivationRequest
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions

  @type t :: %{
          requested: map() | nil,
          operational: map() | nil,
          applied: map() | nil,
          observed: map()
        }

  @spec fetch(binary(), binary()) :: {:ok, t()} | {:error, term()}
  def fetch(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    requested = requested_intent(organization_id, mission_id)
    operational = operational_basis(organization_id, mission_id)
    applied = applied_basis(mission_id)

    {:ok,
     %{
       requested: requested,
       operational: operational,
       applied: applied,
       observed: observed_state(requested, operational, applied)
     }}
  end

  defp requested_intent(organization_id, mission_id) do
    case ManagementActivations.latest_request(organization_id, mission_id) do
      %ActivationRequest{} = request ->
        %{
          activation_request_id: request.activation_request_id,
          state: request.state,
          binding_set_id: request.binding_set_id,
          binding_set_version: request.binding_set_version,
          binding_set_content_sha256: request.binding_set_content_sha256,
          change_class: request.change_class,
          requested_at: request.requested_at,
          decided_at: request.decided_at
        }

      nil ->
        nil
    end
  end

  defp operational_basis(organization_id, mission_id) do
    case ControlActivations.fetch_active_basis(organization_id, mission_id) do
      {:ok, %BindingSetActivation{} = activation} ->
        %{
          activation_request_id: activation.activation_request_id,
          activation_id: activation.activation_id,
          generation: activation.generation,
          binding_set_id: activation.binding_set_id,
          binding_set_version: activation.binding_set_version,
          binding_set_content_sha256: activation.binding_set_content_sha256,
          execution: execution_state(activation.activation_request_id)
        }

      {:error, :no_active_binding_set} ->
        nil
    end
  end

  defp applied_basis(mission_id) do
    case RuntimeMissions.applied_spec(mission_id) do
      {:ok, %MissionRuntimeSpec{} = spec} ->
        %{
          activation_request_id: spec.activation_request_id,
          activation_id: spec.activation_id,
          generation: spec.generation,
          binding_set_id: spec.binding_set_id,
          binding_set_version: spec.binding_set_version,
          binding_set_content_sha256: spec.binding_set_content_sha256
        }

      {:error, reason} when reason in [:mission_runtime_not_running, :no_active_binding_set] ->
        nil
    end
  end

  defp execution_state(nil), do: nil

  defp execution_state(activation_request_id) do
    case ControlActivations.fetch_execution(activation_request_id) do
      {:ok, %ActivationExecution{} = execution} ->
        %{
          activation_execution_id: execution.activation_execution_id,
          status: execution.status,
          generation: execution.generation,
          completed_at: execution.completed_at
        }

      {:error, :activation_execution_not_found} ->
        nil
    end
  end

  defp observed_state(requested, operational, applied) do
    operational
    |> generation_observation(applied)
    |> Map.put(:request_alignment, request_alignment(requested, operational))
  end

  defp generation_observation(nil, nil) do
    %{mission_runtime: :stopped, generation_alignment: :no_operational_generation}
  end

  defp generation_observation(%{generation: operational_generation}, nil) do
    %{
      mission_runtime: :stopped,
      generation_alignment: :not_applied,
      operational_generation: operational_generation,
      applied_generation: nil
    }
  end

  defp generation_observation(%{generation: generation}, %{generation: generation}) do
    %{
      mission_runtime: :running,
      generation_alignment: :converged,
      operational_generation: generation,
      applied_generation: generation
    }
  end

  defp generation_observation(%{generation: operational}, %{generation: applied}) do
    %{
      mission_runtime: :running,
      generation_alignment: :diverged,
      operational_generation: operational,
      applied_generation: applied
    }
  end

  defp generation_observation(nil, %{generation: applied}) do
    %{
      mission_runtime: :running,
      generation_alignment: :orphaned,
      operational_generation: nil,
      applied_generation: applied
    }
  end

  defp request_alignment(nil, nil), do: :not_requested
  defp request_alignment(%{state: :approval_pending}, _operational), do: :pending_approval
  defp request_alignment(%{state: :rejected}, _operational), do: :rejected

  defp request_alignment(
         %{state: :approved, activation_request_id: request_id},
         %{activation_request_id: request_id}
       ),
       do: :executed

  defp request_alignment(%{state: :approved}, _operational), do: :awaiting_execution
  defp request_alignment(nil, _operational), do: :untracked_operational_basis
end
