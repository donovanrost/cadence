defmodule Cadence.Contacts.ScidMismatchAttention do
  @moduledoc """
  The `contact_scid_mismatch` source of the mission attention read (ux U81 §2, DECISIONS #102):
  a settled pass where MOST of its TM frames carried another SCID (`ScidMismatch.most?/1`, the
  same rule as the `contact_scid_mismatch` event), so they were refused and made no telemetry.
  One item per contact, P2 caution (the pass is over).

  Reads the contact's settlement key (`metadata["settlement"]["scid_mismatch"]`). Lifecycle:
  open from settle; Mark as seen (`acknowledge/3`) RESOLVES it at once (action `seen`, the
  acknowledger) and is kept OUTSIDE the settlement (`metadata["scid_mismatch_ack"]`) so a
  re-settle can't wipe it; never seen, it retires 7 days after settle (action `retired`, by the
  system). So nothing is ever acknowledged-but-open (`counts.acknowledged` is 0).

  Candidates are the mission's contacts realized in the window (the `realized_at` index; a pass
  settles within its settlement deadline of its end), filtered on the settlement key.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{ContactStore, RealizedContact, ScidMismatch}
  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @source "contact_scid_mismatch"
  @retire_after_s 7 * 86_400
  # Realized this long before a settle can still be in the window: the retire period plus slack
  # for long passes and the settlement deadline.
  @lookback_s @retire_after_s + 2 * 86_400
  @ack_key "scid_mismatch_ack"

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    now = DateTime.utc_now()
    contacts = open_contacts(org, mission, now)
    reservations = reservations(org, mission, contacts)

    contacts
    |> Enum.map(&item(&1, Map.get(reservations, &1.scheduled_contact_id)))
    |> Enum.sort_by(& &1.raised_at, DateTime)
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission),
    do: %{open: length(open_contacts(org, mission, DateTime.utc_now())), acknowledged: 0}

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    now = DateTime.utc_now()

    for contact <- candidates(org, mission, DateTime.add(since, -@lookback_s, :second)),
        {action, at, by} <- resolution(contact, now),
        DateTime.compare(at, since) != :lt do
      %{
        id: contact.realized_contact_id,
        source: @source,
        resolved_by: by,
        action: action,
        resolved_at: at
      }
    end
  end

  @doc """
  Marks the pass as seen: resolves the item at once (ux U81 §2). Returns the item with state
  `resolved` and its resolution (action `seen`, the acknowledger), as the other sources do. Not
  open (seen, retired, or never raised): `{:error, :attention_item_not_found}`.
  """
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id) do
    now = DateTime.utc_now()

    with {:ok, actor} <- actor(scope, mission),
         {:ok, contact} <- fetch_open(scope.organization_id, mission, id, now),
         {:ok, updated} <-
           ContactStore.update_realized_lifecycle(contact, contact.lifecycle_state, %{
             @ack_key => %{
               "acknowledged_at" => DateTime.to_iso8601(now),
               "acknowledged_by" => actor
             }
           }) do
      ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)
      reservations = reservations(scope.organization_id, mission, [updated])

      {:ok,
       updated
       |> item(Map.get(reservations, updated.scheduled_contact_id))
       |> Map.merge(%{
         state: "resolved",
         resolution: %{
           action: "seen",
           actor: actor,
           at: now,
           note: nil,
           provider_reference: nil
         }
       })}
    end
  end

  @doc "Not an operator action for this source."
  @spec resolve(Scope.t(), binary(), binary(), String.t()) :: {:error, :attention_item_not_found}
  def resolve(_scope, _mission, _id, _action), do: {:error, :attention_item_not_found}

  @doc "Not an operator action for this source: the pass is over."
  @spec retry(Scope.t(), binary(), binary()) :: {:error, :attention_item_not_found}
  def retry(_scope, _mission, _id), do: {:error, :attention_item_not_found}

  defp resolution(contact, now) do
    case {acknowledgement(contact), retires_at(contact)} do
      {{at, by}, _retires} ->
        [{"seen", at, by}]

      {nil, %DateTime{} = retires} ->
        if past?(retires, now), do: [{"retired", retires, system()}], else: []

      {nil, nil} ->
        []
    end
  end

  defp system, do: %{"kind" => "system"}

  defp open?(contact, now) do
    case {acknowledgement(contact), retires_at(contact)} do
      {nil, %DateTime{} = retires} -> not past?(retires, now)
      _seen_or_unsettled -> false
    end
  end

  defp past?(at, now), do: DateTime.compare(now, at) != :lt

  defp acknowledgement(%RealizedContact{metadata: metadata}) do
    with %{"acknowledged_at" => at} = ack <- (metadata || %{})[@ack_key],
         %DateTime{} = at <- timestamp(at),
         do: {at, ack["acknowledged_by"]},
         else: (_none -> nil)
  end

  defp settled_at(%RealizedContact{metadata: metadata}),
    do: timestamp(get_in(metadata || %{}, ["settlement", "settled_at"]))

  defp retires_at(contact) do
    case settled_at(contact) do
      %DateTime{} = at -> DateTime.add(at, @retire_after_s, :second)
      nil -> nil
    end
  end

  # todo(authz): Cedar should decide who may mark a pass as seen (any operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp fetch_open(org, mission, id, now) do
    with {:ok, %RealizedContact{} = contact} <- ContactStore.fetch_realized(org, mission, id),
         true <- raised?(contact) and open?(contact, now) do
      {:ok, contact}
    else
      _not_open -> {:error, :attention_item_not_found}
    end
  end

  defp raised?(contact), do: contact |> ScidMismatch.entries() |> ScidMismatch.most?()

  defp open_contacts(org, mission, now) do
    org
    |> candidates(mission, DateTime.add(now, -@lookback_s, :second))
    |> Enum.filter(&open?(&1, now))
  end

  # The mission's contacts realized since `from` whose settlement raised the item.
  defp candidates(org, mission, %DateTime{} = from) do
    from(row in RealizedContactRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and row.realized_at >= ^from and
          fragment("? -> 'value' -> 'settlement' -> 'scid_mismatch' IS NOT NULL", row.metadata)
    )
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
    |> Enum.filter(&raised?/1)
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
    entries = ScidMismatch.entries(contact)

    %{
      id: contact.realized_contact_id,
      source: @source,
      conflict: nil,
      state: "open",
      realized_contact_id: contact.realized_contact_id,
      contact_id: contact.scheduled_contact_id,
      provider_reservation_id: reservation && reservation.provider_reservation_id,
      ground_station_ref: ground_station_ref(reservation, entries),
      spacecraft_id: Enum.find_value(entries, & &1["spacecraft_id"]),
      starts_at: contact.realized_at,
      raised_at: settled_at(contact),
      retires_at: retires_at(contact),
      scid_mismatch: entries,
      acknowledged_by: nil,
      resolution: nil
    }
  end

  defp ground_station_ref(reservation, entries) do
    from_booking =
      reservation &&
        Enum.find_value(
          [reservation.provider_confirmed_snapshot_document, reservation.request_document],
          &(is_map(&1) && &1["ground_station_ref"])
        )

    from_booking || Enum.find_value(entries, & &1["ground_station_ref"])
  end

  defp timestamp(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp timestamp(_at), do: nil
end
