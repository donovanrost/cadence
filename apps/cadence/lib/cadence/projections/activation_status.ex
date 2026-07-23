defmodule Cadence.Projections.ActivationStatus do
  @moduledoc """
  Read-side view that keeps desired, applied, and observed activation state
  visibly separate.
  """

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions

  @type t :: %{
          desired: map() | nil,
          applied: map() | nil,
          observed: map()
        }

  @spec fetch(binary(), binary()) :: {:ok, t()} | {:error, term()}
  def fetch(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    desired = desired_basis(organization_id, mission_id)
    applied = applied_basis(mission_id)

    {:ok,
     %{
       desired: desired,
       applied: applied,
       observed: observed_state(desired, applied)
     }}
  end

  defp desired_basis(organization_id, mission_id) do
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

  defp observed_state(nil, nil) do
    %{mission_runtime: :stopped, generation_alignment: :no_desired_generation}
  end

  defp observed_state(%{generation: desired_generation}, nil) do
    %{
      mission_runtime: :stopped,
      generation_alignment: :not_applied,
      desired_generation: desired_generation,
      applied_generation: nil
    }
  end

  defp observed_state(%{generation: generation}, %{generation: generation}) do
    %{
      mission_runtime: :running,
      generation_alignment: :converged,
      desired_generation: generation,
      applied_generation: generation
    }
  end

  defp observed_state(%{generation: desired}, %{generation: applied}) do
    %{
      mission_runtime: :running,
      generation_alignment: :diverged,
      desired_generation: desired,
      applied_generation: applied
    }
  end

  defp observed_state(nil, %{generation: applied}) do
    %{
      mission_runtime: :running,
      generation_alignment: :orphaned,
      desired_generation: nil,
      applied_generation: applied
    }
  end
end
