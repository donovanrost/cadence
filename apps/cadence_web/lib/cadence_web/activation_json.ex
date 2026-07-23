defmodule CadenceWeb.ActivationJSON do
  @moduledoc false

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Management.Activations.{ActivationDecision, ActivationRequest}

  @spec request(ActivationRequest.t()) :: map()
  def request(%ActivationRequest{} = request) do
    %{
      activation_request_id: request.activation_request_id,
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      binding_set_id: request.binding_set_id,
      binding_set_version: request.binding_set_version,
      binding_set_content_sha256: request.binding_set_content_sha256,
      change_class: Atom.to_string(request.change_class),
      state: Atom.to_string(request.state),
      requester_actor: request.requester_actor_document,
      policy: request.policy_document,
      metadata: request.metadata,
      requested_at: iso8601(request.requested_at),
      decided_at: iso8601(request.decided_at)
    }
  end

  @spec decision(ActivationDecision.t()) :: map()
  def decision(%ActivationDecision{} = decision) do
    %{
      activation_decision_id: decision.activation_decision_id,
      activation_request_id: decision.activation_request_id,
      organization_id: decision.organization_id,
      mission_id: decision.mission_id,
      decision: Atom.to_string(decision.decision),
      actor: decision.actor_document,
      reason: decision.reason,
      decided_at: iso8601(decision.decided_at)
    }
  end

  @spec execution(ActivationExecution.t()) :: map()
  def execution(%ActivationExecution{} = execution) do
    %{
      activation_execution_id: execution.activation_execution_id,
      activation_request_id: execution.activation_request_id,
      organization_id: execution.organization_id,
      mission_id: execution.mission_id,
      status: Atom.to_string(execution.status),
      executor_actor: execution.executor_actor_document,
      activation_id: execution.activation_id,
      generation: execution.generation,
      binding_set_content_sha256: execution.binding_set_content_sha256,
      error: execution.error_document,
      started_at: iso8601(execution.started_at),
      completed_at: iso8601(execution.completed_at)
    }
  end

  @spec request_result(ActivationRequest.t(), ActivationExecution.t() | nil) :: map()
  def request_result(%ActivationRequest{} = request, execution) do
    %{
      request: request(request),
      execution: execution && execution(execution)
    }
  end

  @spec approval_result(ActivationRequest.t(), ActivationDecision.t(), ActivationExecution.t()) ::
          map()
  def approval_result(request, decision, execution) do
    %{
      request: request(request),
      decision: decision(decision),
      execution: execution(execution)
    }
  end

  @spec rejection_result(ActivationRequest.t(), ActivationDecision.t()) :: map()
  def rejection_result(request, decision) do
    %{
      request: request(request),
      decision: decision(decision),
      execution: nil
    }
  end

  @spec activation(BindingSetActivation.t()) :: map()
  def activation(%BindingSetActivation{} = activation) do
    %{
      activation_id: activation.activation_id,
      activation_request_id: activation.activation_request_id,
      organization_id: activation.organization_id,
      mission_id: activation.mission_id,
      generation: activation.generation,
      binding_set_id: activation.binding_set_id,
      binding_set_version: activation.binding_set_version,
      binding_set_content_sha256: activation.binding_set_content_sha256,
      activated_at: iso8601(activation.activated_at),
      metadata: activation.metadata
    }
  end

  @spec active_binding_set(BindingSetActivation.t(), BindingSet.t()) :: map()
  def active_binding_set(%BindingSetActivation{} = activation, %BindingSet{} = binding_set) do
    %{
      activation: activation(activation),
      binding_set: CadenceWeb.ControlPlaneJSON.binding_set(binding_set)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
