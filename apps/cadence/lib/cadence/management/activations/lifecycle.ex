defmodule Cadence.Management.Activations.Lifecycle do
  @moduledoc """
  An activation request leaving `approval_pending` other than by a decision (L10, fe-setup's
  activations plan): the requester withdraws it, or a newer request supersedes it.

  - Withdraw: the requester only (`:not_requester` otherwise), recorded as a `withdrawn` decision
    by the requester with their reason.
  - Supersede: a new request supersedes older pending ones for the same thing, in the creating
    transaction. A decom composition (or any other binding set) supersedes by `binding_set_id`; a
    spacecraft-configuration request (they all share the mission's decom binding set) supersedes
    older pending requests whose reviewed spacecraft overlap its own. Each superseded row records
    `superseded_by` and `superseded_at`, with no decision row (it's the system's, not a person's),
    and an `activation_superseded` audit event.

  Every path locks the request row and re-checks `approval_pending` inside its transaction, so an
  approve can't land on a request superseded a moment earlier.
  """

  import Ecto.Query

  alias Cadence.Auth.Scope
  alias Cadence.Catalog.SpacecraftModelBindings
  alias Cadence.Management.Activations.{ActivationDecision, ActivationDecisionRow}
  alias Cadence.Management.Activations.{ActivationRequest, ActivationRequestRow}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @doc """
  Withdraws a pending request (its requester only). `{:ok, request, decision}`, or `{:error,
  :activation_request_not_found | :not_requester | :activation_request_not_pending_approval |
  :invalid_reason}`.
  """
  def withdraw(%Scope{user: %{user_id: user_id}} = scope, request_id, reason)
      when is_binary(request_id) do
    with :ok <- reason(reason),
         {:ok, {request, decision}} <-
           Repo.transaction(fn -> withdraw_locked(scope, user_id, request_id, reason) end) do
      {:ok, request, decision}
    end
  end

  def withdraw(_scope, _request_id, _reason), do: {:error, :not_requester}

  @doc """
  Supersedes the pending requests `request` replaces. Runs inside the transaction that inserts
  `request`; returns the superseded ids.
  """
  def supersede_older(%ActivationRequest{} = request) do
    now = DateTime.utc_now()

    request
    |> candidates()
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.filter(&replaces?(request, &1))
    |> Enum.map(fn row ->
      row
      |> Ecto.Changeset.change(
        state: :superseded,
        superseded_by: request.activation_request_id,
        superseded_at: now
      )
      |> Repo.update!()

      {:ok, _event} = audit(row, request, now)
      row.activation_request_id
    end)
  end

  defp withdraw_locked(scope, user_id, request_id, reason) do
    row = locked(scope.organization_id, request_id)

    cond do
      is_nil(row) -> Repo.rollback(:activation_request_not_found)
      row.requester_actor_id != user_id -> Repo.rollback(:not_requester)
      row.state != :approval_pending -> Repo.rollback(:activation_request_not_pending_approval)
      true -> withdrawn(scope, row, String.trim(reason))
    end
  end

  defp withdrawn(scope, row, reason) do
    now = DateTime.utc_now()

    actor = %{
      "kind" => "user",
      "id" => scope.user.user_id,
      "display_name" => Map.get(scope.user, :display_name)
    }

    decision =
      ActivationDecision.new(%{
        activation_request_id: row.activation_request_id,
        organization_id: row.organization_id,
        mission_id: row.mission_id,
        decision: :withdrawn,
        actor_kind: :user,
        actor_id: scope.user.user_id,
        actor_document: actor,
        reason: reason,
        decided_at: now
      })
      |> ActivationDecisionRow.changeset()
      |> Repo.insert!()

    updated = row |> ActivationRequestRow.state_changeset(:withdrawn, now) |> Repo.update!()

    {ActivationRequestRow.to_domain(updated), ActivationDecisionRow.to_domain(decision)}
  end

  defp locked(organization_id, request_id) do
    ActivationRequestRow
    |> where(
      [r],
      r.activation_request_id == ^request_id and r.organization_id == ^organization_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  # Older pending requests of the mission for the same binding set (spacecraft-configuration
  # requests share theirs; replaces?/2 narrows those to overlapping spacecraft).
  defp candidates(request) do
    from(r in ActivationRequestRow,
      where:
        r.organization_id == ^request.organization_id and r.mission_id == ^request.mission_id and
          r.binding_set_id == ^request.binding_set_id and r.state == :approval_pending and
          r.activation_request_id != ^request.activation_request_id,
      order_by: r.activation_request_id
    )
  end

  defp replaces?(%{metadata: %{"spacecraft_configuration_version" => _} = metadata}, row) do
    case {reviewed(metadata), reviewed(JsonDocument.unwrap_value(row.metadata) || %{})} do
      {[_ | _] = new, [_ | _] = old} -> Enum.any?(new, &(&1 in old))
      _unknown -> false
    end
  end

  defp replaces?(_request, _row), do: true

  defp reviewed(%{"change_set" => %{"spacecraft_ids" => ids}}) when is_list(ids), do: ids

  defp reviewed(metadata) do
    case SpacecraftModelBindings.reviewed_spacecraft_ids(metadata) do
      {:ok, ids} -> ids
      {:error, _not_reviewed} -> []
    end
  end

  defp audit(row, request, now) do
    %{
      event_id: "operational_event:activation_request:#{row.activation_request_id}:superseded",
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      occurred_at: now,
      recorded_at: now,
      effective_at: now,
      category: :runtime,
      kind: :activation_superseded,
      severity: :info,
      actor: %{kind: :system},
      subject: %{kind: :binding_set, id: row.binding_set_id},
      causality: %{
        correlation_id: request.activation_request_id,
        source_record_kind: :activation_request,
        source_record_id: "#{row.activation_request_id}:superseded"
      },
      payload: %{
        activation_request_id: row.activation_request_id,
        superseded_by: request.activation_request_id
      }
    }
    |> Event.new()
    |> OperationalEvents.persist_event()
  end

  defp reason(reason) when is_binary(reason) do
    if String.trim(reason) != "" and String.length(reason) <= 4096,
      do: :ok,
      else: {:error, :invalid_reason}
  end

  defp reason(_reason), do: {:error, :invalid_reason}
end
