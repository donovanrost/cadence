defmodule Cadence.Management.Activations do
  @moduledoc """
  Management-plane workflow for activation request and human approval.
  """

  import Ecto.Query

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Governance

  alias Cadence.Management.Activations.{
    ActivationDecision,
    ActivationDecisionRow,
    ActivationRequest,
    ActivationRequestRow,
    ApprovedActivation
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo

  @change_classes [
    :observational,
    :mission_data_plane,
    :transport_provider,
    :command_safety,
    :identity_policy
  ]

  @spec request(Scope.t(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, ActivationRequest.t()} | {:error, term()}
  def request(%Scope{} = current_scope, mission_id, binding_set_id, version, opts \\ [])
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    organization_id = current_scope.organization_id
    change_class = Keyword.get(opts, :change_class, :mission_data_plane)
    requested_at = now(opts)

    with :ok <- valid_change_class(change_class),
         :ok <- authorize_request(current_scope, mission_id, change_class),
         {:ok, requester_actor} <- actor(current_scope),
         {:ok, %BindingSet{} = binding_set} <-
           Governance.fetch_binding_set(
             organization_id,
             mission_id,
             binding_set_id,
             version
           ) do
      current_scope
      |> build_request(binding_set, requester_actor, change_class, requested_at)
      |> persist_request()
    end
  end

  @spec approve(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, ActivationRequest.t(), ActivationDecision.t(), ApprovedActivation.t()}
          | {:error, term()}
  def approve(%Scope{} = current_scope, request_id, reason, opts \\ []) do
    decide(current_scope, request_id, :approved, reason, opts)
  end

  @spec reject(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, ActivationRequest.t(), ActivationDecision.t()} | {:error, term()}
  def reject(%Scope{} = current_scope, request_id, reason, opts \\ []) do
    decide(current_scope, request_id, :rejected, reason, opts)
  end

  @spec fetch(Scope.t(), binary()) :: {:ok, ActivationRequest.t()} | {:error, term()}
  def fetch(%Scope{} = current_scope, request_id) when is_binary(request_id) do
    case Repo.get_by(ActivationRequestRow,
           activation_request_id: request_id,
           organization_id: current_scope.organization_id
         ) do
      nil -> {:error, :activation_request_not_found}
      row -> {:ok, ActivationRequestRow.to_domain(row)}
    end
  end

  @spec fetch_approved(binary()) :: {:ok, ApprovedActivation.t()} | {:error, term()}
  def fetch_approved(request_id) when is_binary(request_id) do
    with %ActivationRequestRow{} = row <- Repo.get(ActivationRequestRow, request_id),
         :approved <- row.state do
      decisions = approved_decisions(request_id)
      {:ok, approved_handoff(row, decisions)}
    else
      nil -> {:error, :activation_request_not_found}
      _state -> {:error, :activation_request_not_approved}
    end
  end

  defp decide(current_scope, request_id, decision, reason, opts)
       when is_binary(request_id) and decision in [:approved, :rejected] and is_list(opts) do
    reason = reason |> to_string() |> String.trim()
    decided_at = now(opts)

    with :ok <- require_reason(reason),
         {:ok, approver_actor} <- human_approver(current_scope) do
      current_scope
      |> transact_decision(request_id, decision, approver_actor, reason, decided_at)
      |> decision_result(decision)
    end
  end

  defp decide(_scope, _request_id, _decision, _reason, _opts),
    do: {:error, :invalid_activation_decision}

  defp authorize_request(scope, mission_id, change_class) do
    Policy.authorize(scope, :request_activation, %{
      organization_id: scope.organization_id,
      mission_id: mission_id,
      change_class: change_class
    })
  end

  defp build_request(scope, binding_set, requester_actor, change_class, requested_at) do
    approval_required? = approval_required?()

    ActivationRequest.new(%{
      organization_id: scope.organization_id,
      mission_id: binding_set.mission_id,
      binding_set_id: binding_set.binding_set_id,
      binding_set_version: binding_set.version,
      binding_set_content_sha256: ContentHash.term_sha256(binding_set),
      change_class: change_class,
      state: request_state(approval_required?),
      requester_actor_kind: scope.actor_kind,
      requester_actor_id: requester_actor["id"],
      requester_actor_document: requester_actor,
      policy_document: request_policy(approval_required?),
      requested_at: requested_at,
      decided_at: decided_at(approval_required?, requested_at)
    })
  end

  defp persist_request(request) do
    request
    |> ActivationRequestRow.changeset()
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, ActivationRequestRow.to_domain(row)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp request_state(true), do: :approval_pending
  defp request_state(false), do: :approved

  defp decided_at(true, _requested_at), do: nil
  defp decided_at(false, requested_at), do: requested_at

  defp request_policy(approval_required?) do
    %{
      "policy" => "activation_release_one",
      "approval_required" => approval_required?,
      "required_human_approvals" => if(approval_required?, do: 1, else: 0),
      "separation_of_duties" => approval_required?
    }
  end

  defp transact_decision(scope, request_id, decision, actor, reason, decided_at) do
    Repo.transaction(fn ->
      persist_decision(scope, request_id, decision, actor, reason, decided_at)
    end)
  end

  defp persist_decision(scope, request_id, decision, actor, reason, decided_at) do
    with {:ok, request_row} <- lock_pending_request(scope, request_id),
         :ok <- authorize_decision(scope, request_row),
         :ok <- distinct_approver(request_row, actor),
         {:ok, decision_row} <-
           insert_decision(request_row, request_id, decision, actor, reason, decided_at),
         {:ok, updated_request_row} <- update_decided_request(request_row, decision, decided_at) do
      {updated_request_row, decision_row}
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp authorize_decision(scope, request_row) do
    Policy.authorize(scope, :approve_activation, %{
      organization_id: request_row.organization_id,
      mission_id: request_row.mission_id,
      change_class: request_row.change_class
    })
  end

  defp insert_decision(request_row, request_id, decision, actor, reason, decided_at) do
    request_row
    |> activation_decision(request_id, decision, actor, reason, decided_at)
    |> ActivationDecisionRow.changeset()
    |> Repo.insert()
  end

  defp activation_decision(request_row, request_id, decision, actor, reason, decided_at) do
    ActivationDecision.new(%{
      activation_request_id: request_id,
      organization_id: request_row.organization_id,
      mission_id: request_row.mission_id,
      decision: decision,
      actor_kind: :user,
      actor_id: actor["id"],
      actor_document: actor,
      reason: reason,
      decided_at: decided_at
    })
  end

  defp update_decided_request(request_row, decision, decided_at) do
    request_row
    |> ActivationRequestRow.state_changeset(decision, decided_at)
    |> Repo.update()
  end

  defp lock_pending_request(%Scope{} = scope, request_id) do
    ActivationRequestRow
    |> where(
      [request],
      request.activation_request_id == ^request_id and
        request.organization_id == ^scope.organization_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :activation_request_not_found}
      %ActivationRequestRow{state: :approval_pending} = row -> {:ok, row}
      _row -> {:error, :activation_request_not_pending_approval}
    end
  end

  defp approved_decisions(request_id) do
    ActivationDecisionRow
    |> where(
      [decision],
      decision.activation_request_id == ^request_id and decision.decision == :approved
    )
    |> order_by([decision], asc: decision.decided_at, asc: decision.activation_decision_id)
    |> Repo.all()
  end

  defp approved_handoff(request_row, decision_rows) do
    %ApprovedActivation{
      activation_request_id: request_row.activation_request_id,
      organization_id: request_row.organization_id,
      mission_id: request_row.mission_id,
      binding_set_id: request_row.binding_set_id,
      binding_set_version: request_row.binding_set_version,
      binding_set_content_sha256: request_row.binding_set_content_sha256,
      change_class: request_row.change_class,
      requester_actor_document: JsonDocument.unwrap_value(request_row.requester_actor_document),
      approval_decision_ids: Enum.map(decision_rows, & &1.activation_decision_id),
      policy_document: JsonDocument.unwrap_value(request_row.policy_document),
      approved_at: request_row.decided_at
    }
  end

  defp decision_result({:ok, {request_row, decision_row}}, :approved) do
    request = ActivationRequestRow.to_domain(request_row)
    decision = ActivationDecisionRow.to_domain(decision_row)
    {:ok, request, decision, approved_handoff(request_row, [decision_row])}
  end

  defp decision_result({:ok, {request_row, decision_row}}, :rejected) do
    {:ok, ActivationRequestRow.to_domain(request_row),
     ActivationDecisionRow.to_domain(decision_row)}
  end

  defp decision_result({:error, reason}, _decision), do: {:error, reason}

  defp actor(%Scope{actor_kind: :user, user: user}) when not is_nil(user) do
    {:ok,
     %{
       "kind" => "user",
       "id" => user.user_id,
       "display_name" => user.display_name,
       "email" => user.email
     }}
  end

  defp actor(%Scope{actor_kind: :service, service_identity: identity})
       when not is_nil(identity) do
    {:ok,
     %{
       "kind" => "service",
       "id" => identity.service_identity_id,
       "display_name" => identity.display_name
     }}
  end

  defp actor(%Scope{}), do: {:error, :authenticated_actor_required}

  defp human_approver(%Scope{actor_kind: :user} = scope), do: actor(scope)

  defp human_approver(%Scope{actor_kind: :service}),
    do: {:error, :human_activation_approver_required}

  defp distinct_approver(request_row, approver_actor) do
    if request_row.requester_actor_kind == :user and
         request_row.requester_actor_id == approver_actor["id"] do
      {:error, :activation_self_approval_forbidden}
    else
      :ok
    end
  end

  defp valid_change_class(change_class) when change_class in @change_classes, do: :ok
  defp valid_change_class(_change_class), do: {:error, :invalid_activation_change_class}
  defp require_reason(""), do: {:error, :activation_decision_reason_required}
  defp require_reason(_reason), do: :ok

  defp approval_required? do
    :cadence
    |> Application.get_env(:activation_governance, [])
    |> Keyword.get(:approval_required, true)
  end

  defp now(opts) do
    datetime = Keyword.get(opts, :now, DateTime.utc_now())
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
