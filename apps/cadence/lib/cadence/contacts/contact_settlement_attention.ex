defmodule Cadence.Contacts.ContactSettlementAttention do
  @moduledoc """
  The `contact_settlement` source of the mission attention read (DECISIONS #71, ux U37): an
  ended contact whose telemetry is still in its on-disk journal, not yet stored
  (`settlement.state` `"unsettled"`). Conflict `unsettled`; `reason` is `settle_deadline` or
  `settle_failed`, and `failure_kind` groups same-cause items.

  Derived from the durable settlement. The journal is never pruned past its processing cursor,
  so the item has no expiry (`expires_at` nil, always P2). Cadence retries by itself (`retry`
  `"automatic"`): the item resolves (`resolved_by` kind `system`, action `replayed`) when
  replaying the journal settles the contact.

  With the ingress journal off, an unsettled backlog was only in memory and is gone
  (`backlog.lost`). Nothing can replay it, so only an operator closes that item: `acknowledge/3`
  (ux U37 "Mark as seen"; director 2026-11-12), recorded with who and when. It is the only
  operator action; acknowledging a recoverable item, and `resolve/4`, are not found.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{ContactSettlement, ContactStore}
  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @source "contact_settlement"
  @epoch ~U[1970-01-01 00:00:00Z]

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    contacts =
      org |> open_query(mission) |> Repo.all() |> Enum.map(&RealizedContactRow.to_domain/1)

    reservations = reservations(org, mission, contacts)

    contacts
    |> Enum.map(&item(&1, Map.get(reservations, &1.scheduled_contact_id)))
    |> Enum.sort_by(&(&1.raised_at || @epoch), DateTime)
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    replayed =
      for contact <- in_state(org, mission, "settled"),
          replayed_at = timestamp(contact.metadata["settlement"]["replayed_at"]),
          replayed_at != nil and DateTime.compare(replayed_at, since) != :lt do
        %{
          id: contact.realized_contact_id,
          source: @source,
          resolved_by: %{"kind" => "system"},
          action: "replayed",
          resolved_at: replayed_at
        }
      end

    acknowledged =
      for contact <- in_state(org, mission, "unsettled"),
          settlement = contact.metadata["settlement"],
          at = timestamp(settlement["acknowledged_at"]),
          at != nil and DateTime.compare(at, since) != :lt do
        %{
          id: contact.realized_contact_id,
          source: @source,
          resolved_by: settlement["acknowledged_by"],
          action: "acknowledged",
          resolved_at: at
        }
      end

    replayed ++ acknowledged
  end

  @doc """
  Closes a lost item (journal off: the backlog is gone) as seen by the operator. Anything else,
  including a recoverable item, is `{:error, :attention_item_not_found}`.
  """
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id) do
    with {:ok, actor} <- actor(scope, mission),
         {:ok, contact} <- fetch_lost(scope.organization_id, mission, id),
         at = DateTime.utc_now(),
         settlement =
           Map.merge(contact.metadata["settlement"], %{
             "acknowledged_at" => DateTime.to_iso8601(at),
             "acknowledged_by" => actor
           }),
         {:ok, updated} <-
           ContactStore.update_realized_lifecycle(contact, contact.lifecycle_state, %{
             "settlement" => settlement
           }) do
      ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)

      {:ok,
       updated
       |> item(nil)
       |> Map.merge(%{
         state: "resolved",
         acknowledged_by: actor,
         resolution: %{
           action: "acknowledged",
           actor: actor,
           at: at,
           note: nil,
           provider_reference: nil
         }
       })}
    end
  end

  @doc """
  Starts replay again for a contact whose replay stopped after 6 failed attempts (`retry`
  `manual`): attempts reset, due at the next reconcile. `{:error, {:retry_not_manual, item}}`
  while Cadence is still retrying (a double click or a stale screen gets the item back).
  """
  @spec retry(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def retry(%Scope{} = scope, mission, id) do
    with {:ok, _actor} <- actor(scope, mission),
         {:ok, contact} <- fetch_open(scope.organization_id, mission, id) do
      reservation =
        Map.get(
          reservations(scope.organization_id, mission, [contact]),
          contact.scheduled_contact_id
        )

      case ContactSettlement.retry(contact) do
        {:ok, updated} ->
          ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)
          {:ok, item(updated, reservation)}

        {:error, :retry_not_manual} ->
          {:error, {:retry_not_manual, item(contact, reservation)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_open(org, mission, id) do
    case ContactStore.fetch_realized(org, mission, id) do
      {:ok,
       %RealizedContact{metadata: %{"settlement" => %{"state" => "unsettled"} = s}} = contact}
      when not is_map_key(s, "acknowledged_at") ->
        {:ok, contact}

      _other ->
        {:error, :attention_item_not_found}
    end
  end

  @doc "Not an operator action for this source."
  @spec resolve(Scope.t(), binary(), binary(), String.t()) :: {:error, :attention_item_not_found}
  def resolve(_scope, _mission, _id, _action), do: {:error, :attention_item_not_found}

  # todo(authz): Cedar should decide who may mark lost telemetry as seen (any operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp fetch_lost(org, mission, id) do
    case ContactStore.fetch_realized(org, mission, id) do
      {:ok,
       %RealizedContact{
         metadata: %{
           "settlement" => %{"state" => "unsettled", "backlog" => %{"lost" => true}} = s
         }
       } = contact}
      when not is_map_key(s, "acknowledged_at") ->
        {:ok, contact}

      _other ->
        {:error, :attention_item_not_found}
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission) do
    open =
      org
      |> open_query(mission)
      |> select([row], count(row.realized_contact_id))
      |> Repo.one()

    %{open: open, acknowledged: 0}
  end

  defp open_query(org, mission) do
    org
    |> state_query(mission, "unsettled")
    |> where(
      [row],
      fragment("? -> 'value' -> 'settlement' -> 'acknowledged_at' IS NULL", row.metadata)
    )
  end

  defp in_state(org, mission, state) do
    org
    |> state_query(mission, state)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  defp state_query(org, mission, state) do
    from(row in RealizedContactRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          fragment("? -> 'value' -> 'settlement' ->> 'state' = ?", row.metadata, ^state)
    )
  end

  defp reservations(_org, _mission, []), do: %{}

  defp reservations(org, mission, contacts) do
    ids = contacts |> Enum.map(& &1.scheduled_contact_id) |> Enum.reject(&is_nil/1)

    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.scheduled_contact_id in ^ids
    )
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
    |> Map.new(&{&1.scheduled_contact_id, &1})
  end

  defp item(%RealizedContact{} = contact, reservation) do
    settlement = contact.metadata["settlement"] || %{}

    %{
      id: contact.realized_contact_id,
      source: @source,
      conflict: "unsettled",
      state: "open",
      reason: settlement["reason"],
      failure_kind: settlement["failure_kind"],
      failure_message: settlement["failure_message"],
      contact_id: contact.scheduled_contact_id,
      realized_contact_id: contact.realized_contact_id,
      raised_at: timestamp(settlement["unsettled_at"]),
      deadline_at: timestamp(settlement["deadline_at"]),
      journal: settlement["journal"] || "enabled",
      backlog: backlog(settlement["backlog"] || %{}),
      expires_at: nil,
      # Replay (#71 follow-up): attempts so far, automatic until 6 fail, then manual.
      retry: settlement["retry"] || "automatic",
      attempts: settlement["attempts"] || 0,
      next_attempt_at: timestamp(settlement["next_attempt_at"]),
      last_attempt_at: timestamp(settlement["last_attempt_at"]),
      first_failure_kind: first_failure_kind(settlement),
      acknowledged_by: nil,
      provider_message: nil,
      resolution: nil
    }
    |> Map.merge(pass(reservation))
  end

  defp first_failure_kind(%{"first_failure_kind" => first, "failure_kind" => latest})
       when first != latest,
       do: first

  defp first_failure_kind(_settlement), do: nil

  defp backlog(backlog) do
    %{
      entries: Map.get(backlog, "entries", 0),
      bytes: Map.get(backlog, "bytes", 0),
      journals: Map.get(backlog, "journals", 0),
      queued: Map.get(backlog, "queued", 0),
      lost: Map.get(backlog, "lost", false)
    }
  end

  # The pass the contact realized, from its booking; nil fields for a contact without one.
  defp pass(nil) do
    %{
      spacecraft_id: nil,
      provider_reservation_id: nil,
      ground_station_ref: nil,
      provider_id: nil,
      starts_at: nil,
      ends_at: nil
    }
  end

  defp pass(reservation) do
    %{
      spacecraft_id: reservation.spacecraft_id,
      provider_reservation_id: reservation.provider_reservation_id,
      ground_station_ref: ground_station_ref(reservation),
      provider_id: reservation.provider_id,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at
    }
  end

  defp ground_station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end

  defp timestamp(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp timestamp(_at), do: nil
end
