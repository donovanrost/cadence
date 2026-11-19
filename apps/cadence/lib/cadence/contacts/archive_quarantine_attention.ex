defmodule Cadence.Contacts.ArchiveQuarantineAttention do
  @moduledoc """
  The `archive_quarantine` source of the mission attention read (DECISIONS #88, ux U49): archive
  entries a pass sent that can never be indexed. Their telemetry was still stored; their raw
  records weren't archived. One item per (realized contact, error code). An operator retries
  them once the cause is fixed (synchronous) or discards them with a reason. No acknowledge.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{ContactStore, RealizedContact}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Protocol.RecordArchive.Quarantine
  alias Cadence.Repo

  @source "archive_quarantine"
  @conflict "quarantined"
  @epoch ~U[1970-01-01 00:00:00Z]

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    mission
    |> Quarantine.rows()
    |> Enum.group_by(&{&1.realized_contact_id, &1.error_code})
    |> Enum.map(fn {_key, rows} -> item(org, mission, rows) end)
    |> Enum.sort_by(&(&1.raised_at || @epoch), DateTime)
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission), do: %{open: length(items(org, mission)), acknowledged: 0}

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(_org, mission, %DateTime{} = since) do
    for resolution <- Quarantine.resolutions_since(mission, since) do
      %{
        id: resolution.item_id,
        source: @source,
        conflict: @conflict,
        realized_contact_id: resolution.realized_contact_id,
        spacecraft_id: resolution.spacecraft_id,
        error_code: resolution.error_code,
        counts: resolution.counts,
        resolved_by: resolution.actor,
        action: resolution.action,
        resolved_at: resolution.resolved_at,
        note: resolution.note
      }
    end
  end

  @doc "Not an operator action for this source: retry or discard is the answer (ux U49)."
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:error, :attention_item_not_open}
  def acknowledge(_scope, _mission, _id), do: {:error, :attention_item_not_open}

  @doc "Discard: the entries leave the quarantine, unarchived. The reason is required."
  @spec resolve(Scope.t(), binary(), binary(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def resolve(%Scope{} = scope, mission, id, action_text) do
    note = String.trim(action_text || "")

    with {:ok, actor} <- actor(scope, mission),
         :ok <- if(note == "", do: {:error, :reason_required}, else: :ok),
         {:ok, {contact_id, code}} <- parse(id),
         [_ | _] = rows <- Quarantine.item_rows(mission, contact_id, code),
         item = item(scope.organization_id, mission, rows),
         {:ok, _discarded} <- Quarantine.discard_item(mission, contact_id, code, actor, note) do
      ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)
      {:ok, resolved(item, "discarded", actor, note)}
    else
      [] -> {:error, :attention_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retry, synchronously: `{:ok, %{item, indexed, still_failing}}`. The item is resolved
  (`retried`) when nothing still fails; otherwise it's the open item with `last_retry`.
  """
  @spec retry(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def retry(%Scope{} = scope, mission, id) do
    with {:ok, actor} <- actor(scope, mission),
         {:ok, {contact_id, code}} <- parse(id),
         [_ | _] = rows <- Quarantine.item_rows(mission, contact_id, code),
         before = item(scope.organization_id, mission, rows),
         {:ok, %{indexed: indexed, still_failing: still}} <-
           Quarantine.retry_item(mission, contact_id, code, actor) do
      ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)

      item =
        case Quarantine.item_rows(mission, contact_id, code) do
          [] -> resolved(before, "retried", actor, nil)
          remaining -> item(scope.organization_id, mission, remaining)
        end

      {:ok, %{item: item, indexed: indexed, still_failing: still}}
    else
      [] -> {:error, :attention_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse(id) do
    case Quarantine.parse_item_id(id) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :attention_item_not_found}
    end
  end

  defp resolved(item, action, actor, note) do
    Map.merge(item, %{
      state: "resolved",
      resolution: %{
        action: action,
        actor: actor,
        at: DateTime.utc_now(),
        note: note,
        provider_reference: nil
      }
    })
  end

  defp item(org, mission, [first | _] = rows) do
    counts = Quarantine.counts(rows)
    contact = contact(org, mission, first.realized_contact_id)

    %{
      id: Quarantine.item_id(first.realized_contact_id, first.error_code),
      source: @source,
      conflict: @conflict,
      state: "open",
      raised_at: rows |> Enum.map(& &1.first_seen_at) |> Enum.min(DateTime),
      last_seen_at: rows |> Enum.map(& &1.last_seen_at) |> Enum.max(DateTime),
      expires_at: nil,
      acknowledged_by: nil,
      resolution: nil,
      spacecraft_id: Enum.find_value(rows, & &1.spacecraft_id),
      realized_contact_id: first.realized_contact_id,
      contact_id: contact && contact.scheduled_contact_id,
      error_code: first.error_code,
      error: Enum.find_value(rows, & &1.error),
      counts: counts,
      stored_without_archive: Map.take(counts, [:frames, :packets]),
      first_received_at: span(rows, &Enum.min/2),
      last_received_at: span(rows, &Enum.max/2),
      actions: ["retry", "discard"],
      last_retry: last_retry(rows)
    }
    |> Map.merge(pass(contact, reservation(org, mission, contact)))
  end

  # The pass the entries came from, for the row's title and its Contacts-block placement: the
  # booking when there is one, else the hand-started contact's own station and start.
  defp pass(nil, _reservation), do: pass_fields(nil, nil, nil, nil, nil)

  defp pass(%RealizedContact{}, %{} = reservation) do
    pass_fields(
      reservation.provider_reservation_id,
      ground_station_ref(reservation),
      reservation.provider_id,
      reservation.starts_at,
      reservation.ends_at
    )
  end

  defp pass(%RealizedContact{} = contact, nil),
    do: pass_fields(nil, contact.metadata["ground_station_ref"], nil, contact.realized_at, nil)

  defp pass_fields(reservation_id, station, provider_id, starts_at, ends_at) do
    %{
      provider_reservation_id: reservation_id,
      ground_station_ref: station,
      provider_id: provider_id,
      starts_at: starts_at,
      ends_at: ends_at
    }
  end

  defp reservation(_org, _mission, %RealizedContact{scheduled_contact_id: id} = _contact)
       when not is_binary(id),
       do: nil

  defp reservation(org, mission, %RealizedContact{scheduled_contact_id: id}) do
    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.scheduled_contact_id == ^id,
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> nil
      row -> ProviderReservationRow.to_domain(row)
    end
  end

  defp reservation(_org, _mission, nil), do: nil

  defp ground_station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end

  defp span(rows, pick) do
    case for(%{receipt_time: %DateTime{} = at} <- rows, do: at) do
      [] -> nil
      times -> pick.(times, DateTime)
    end
  end

  defp last_retry(rows) do
    rows
    |> Enum.map(& &1.last_retry)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(& &1["at"], fn -> nil end)
    |> case do
      nil -> nil
      retry -> %{by: retry["by"], at: timestamp(retry["at"]), indexed: retry["indexed"]}
    end
  end

  defp contact(_org, _mission, nil), do: nil

  defp contact(org, mission, id) do
    case ContactStore.fetch_realized(org, mission, id) do
      {:ok, %RealizedContact{} = contact} -> contact
      _missing -> nil
    end
  end

  # todo(authz): Cedar should decide who may retry or discard quarantined archive entries (any
  # mission operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp timestamp(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp timestamp(_at), do: nil
end
