defmodule CadenceWeb.Console.ProviderChangeController do
  @moduledoc """
  §11 L14 (fe-ops' proposal): decide a provider's change to a booked pass, from its
  `provider_change` attention item. `POST …/attention/provider_change/:id/approve | reject |
  acknowledge {reason, proposal_hash}` → the item as it now stands (or null once decided).
  Organization admins decide (`:approve_provider_changes`).
  """

  use CadenceWeb, :controller

  alias Cadence.Contacts.ProviderChangeAttention
  alias Cadence.Control.Contacts
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @actions %{
    approve: &Contacts.approve_provider_change/4,
    reject: &Contacts.reject_provider_change/4,
    acknowledge: &Contacts.acknowledge_provider_change/4
  }
  @stale [
    :stale_provider_change_proposal,
    :provider_change_revision_superseded,
    :provider_change_policy_superseded,
    :provider_change_not_rejectable
  ]

  def approve(conn, params), do: decide(conn, :approve, params)
  def reject(conn, params), do: decide(conn, :reject, params)
  def acknowledge(conn, params), do: decide(conn, :acknowledge, params)

  defp decide(conn, action, %{"id" => id} = params) do
    with %{} <- ProviderChangeAttention.item(org(conn), mission(conn), id) || {:error, :not_open},
         {:ok, reason} <- reason(params["reason"]),
         {:ok, hash} <- hash(params["proposal_hash"]),
         {:ok, _decided} <- Map.fetch!(@actions, action).(scope(conn), id, hash, reason) do
      # The pass row and Now both change: tell the mission channel (qa, L14).
      ScopedReadUpdates.publish(:attention_changed, org(conn), mission(conn))
      ScopedReadUpdates.publish(:contacts_changed, org(conn), mission(conn))
      json(conn, %{data: %{item: current(conn, id)}})
    else
      {:error, reason} -> error(conn, id, reason)
    end
  end

  defp current(conn, id) do
    case ProviderChangeAttention.item(org(conn), mission(conn), id) do
      nil ->
        nil

      item ->
        ConfigJSON.encode(
          AttentionItems.object(item, AttentionItems.lookups(org(conn), mission(conn)))
        )
    end
  end

  defp error(conn, _id, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, _id, :not_open), do: Problem.respond(conn, :attention_item_not_found)

  defp error(conn, id, reason) when reason in @stale,
    do: Problem.respond(conn, :provider_change_stale, %{item: current(conn, id)})

  defp error(conn, id, :provider_change_expired),
    do: Problem.respond(conn, :provider_change_expired, %{item: current(conn, id)})

  defp error(conn, _id, :provider_change_decision_deadline_passed),
    do: Problem.respond(conn, :provider_change_deadline_passed)

  defp error(conn, _id, reason)
       when reason in [:forbidden, :authenticated_user_required, :scope_mismatch] do
    conn
    |> put_status(403)
    |> json(Problem.body("forbidden", "Org admins decide provider changes.", nil))
  end

  defp error(conn, _id, _reason), do: Problem.respond(conn, :attention_item_not_found)

  defp reason(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:error, {:invalid_params, %{reason: "Say why."}}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp reason(_text), do: {:error, {:invalid_params, %{reason: "Say why."}}}

  defp hash(value) when is_binary(value) and byte_size(value) == 64, do: {:ok, value}

  defp hash(_value),
    do: {:error, {:invalid_params, %{proposal_hash: "must be the change's proposal_hash"}}}

  defp scope(conn), do: conn.assigns.current_scope
  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
