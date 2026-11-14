defmodule Cadence.Contacts.ListenerRefusalAttention do
  @moduledoc """
  The `listener_refusal` source of the mission attention read (DECISIONS #87, ux U50): a pass
  whose provider profile shares one listener (`"listener" => "shared"`) while Cadence refuses
  connections on it that it can't match to exactly one pass. One item per contact and listen
  profile, id `<realized_contact_id>:<provider_binding_id>`, from the adapter's refusal window
  (read live through `Cadence.Control.Contacts.listener_refusals/1`):

  - open while the window is: a refusal opened it, and nothing has resolved it;
  - P1 while the pass isn't connected, or its own connection went quiet before the last refusal
    (`own_quiet_since`); otherwise P2. Not acknowledgeable; no actions;
  - resolved `accepted` when the pass's own connection arrives (live), and `ended` when the
    contact ends with the window open: its settler records the summary in the contact's
    `metadata["listener_refusal"]` at LOS (`settlement_document/2`), so the resolution and the
    count outlive the adapter.

  Every contact registered on the listener hears each refusal, so each open pass on it gets its
  own row (`shared_with` names the others). Counts are live: a restart starts them again.
  Contract: docs/apogee/api/ops.md.
  """

  import Ecto.Query

  alias Cadence.Contacts.{ContactStore, ProfileStore, RealizedContact}
  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Control.Contacts, as: Runtime
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @source "listener_refusal"
  @metadata_key "listener_refusal"
  # How far back an ended contact's resolution is looked for (contacts last hours).
  @ended_lookback_s 2 * 24 * 3_600

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    open =
      for %{refusals: %{resolved: nil}} = adapter <- Runtime.listener_refusals(mission),
          do: adapter

    context = context(org, mission, open)
    Enum.map(open, &item(&1, context))
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    accepted =
      for %{refusals: %{resolved: %{at: at} = resolved}} = adapter <-
            Runtime.listener_refusals(mission),
          DateTime.compare(at, since) != :lt,
          do: {adapter.realized_contact_id, adapter.provider_binding_id, resolved.action, at}

    context = context(org, mission, Enum.map(accepted, &%{realized_contact_id: elem(&1, 0)}))

    Enum.map(accepted, &resolution(&1, context)) ++ ended_since(org, mission, since)
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(_org, mission) do
    open =
      Enum.count(Runtime.listener_refusals(mission), &match?(%{refusals: %{resolved: nil}}, &1))

    %{open: open, acknowledged: 0}
  end

  @doc """
  The contact's refusals as its settler records them at LOS, `%{provider_binding_id => doc}`
  (nil when it had no shared listener). An open window is resolved `ended` at `now`.
  """
  @spec settlement_document([map()], DateTime.t()) :: map() | nil
  def settlement_document([], _now), do: nil

  def settlement_document(adapters, %DateTime{} = now) do
    Map.new(adapters, fn adapter ->
      window = adapter.refusals

      {adapter.provider_binding_id,
       %{
         "path_id" => adapter.path_id,
         "second_connections_refused" => adapter.second_connections_refused,
         "shared_with" => adapter.shared_with,
         "refused_count" => window && window.count,
         "first_at" => window && iso(window.first_at),
         "last_at" => window && iso(window.last_at),
         "last" => window && last_document(window.last),
         "resolution" => window && resolution_document(window.resolved, now)
       }}
    end)
  end

  @doc """
  Second connections refused for the contact (ux U50 Technical details): the live count while it
  runs, else what its settler recorded at LOS, else nil (no shared listener, or a live count
  lost to a restart before it settled).
  """
  @spec second_connections_refused(binary(), binary(), binary()) :: non_neg_integer() | nil
  def second_connections_refused(org, mission, realized_contact_id) do
    case Runtime.listener_refusals(mission, realized_contact_id) do
      [_ | _] = live ->
        live |> Enum.map(& &1.second_connections_refused) |> Enum.sum()

      [] ->
        recorded_second_connections(org, mission, realized_contact_id)
    end
  end

  defp recorded_second_connections(org, mission, realized_contact_id) do
    case ContactStore.fetch_realized(org, mission, realized_contact_id) do
      {:ok, %RealizedContact{metadata: %{@metadata_key => %{} = by_binding}}} ->
        by_binding
        |> Map.values()
        |> Enum.map(&(&1["second_connections_refused"] || 0))
        |> Enum.sum()

      _none ->
        nil
    end
  end

  defp item(adapter, context) do
    window = adapter.refusals
    contact = adapter.realized_contact_id
    pass = pass(context, contact)
    quiet_since = window.last[:own_quiet_since]

    %{
      id: id(contact, adapter.provider_binding_id),
      source: @source,
      conflict: @source,
      state: "open",
      realized_contact_id: contact,
      contact_id: scheduled_contact_id(context, contact),
      path_id: adapter.path_id,
      provider_profile_id: adapter.provider_binding_id,
      provider_profile_name: profile_name(context, adapter.provider_binding_id),
      raised_at: window.first_at,
      last_refused_at: window.last_at,
      refused_count: window.count,
      last_refusal: Map.take(window.last, [:reason, :scid, :peer, :at]),
      own_quiet_since: quiet_since,
      connected: adapter.connected?,
      shared_with: adapter.shared_with,
      second_connections_refused: adapter.second_connections_refused,
      acknowledged_by: nil,
      resolution: nil,
      p1: not adapter.connected? or not is_nil(quiet_since)
    }
    |> Map.merge(pass)
  end

  defp resolution({contact, binding, action, at}, context) do
    %{
      id: id(contact, binding),
      source: @source,
      realized_contact_id: contact,
      provider_reservation_id: pass(context, contact).provider_reservation_id,
      resolved_by: "system",
      action: action,
      resolved_at: at
    }
  end

  # Contacts that ended with the window open: their settler recorded resolution "ended".
  defp ended_since(org, mission, since) do
    from(row in RealizedContactRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.inserted_at >= ^DateTime.add(since, -@ended_lookback_s) and
          fragment("(?->'value') \\? ?", row.metadata, ^@metadata_key)
    )
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
    |> Enum.flat_map(&ended_resolutions(&1, org, mission, since))
  end

  defp ended_resolutions(%RealizedContact{} = contact, org, mission, since) do
    for {binding, %{"resolution" => %{"action" => "ended", "at" => at}}} <-
          contact.metadata[@metadata_key],
        {:ok, at, _offset} <- [DateTime.from_iso8601(at)],
        DateTime.compare(at, since) != :lt do
      %{
        id: id(contact.realized_contact_id, binding),
        source: @source,
        realized_contact_id: contact.realized_contact_id,
        provider_reservation_id: reservation_id(org, mission, contact.scheduled_contact_id),
        resolved_by: "system",
        action: "ended",
        resolved_at: at
      }
    end
  end

  defp id(contact, binding), do: "#{contact}:#{binding}"

  defp last_document(last) do
    %{
      "reason" => last.reason,
      "scid" => last.scid,
      "peer" => last.peer,
      "at" => iso(last.at),
      "own_quiet_since" => iso(last[:own_quiet_since])
    }
  end

  defp resolution_document(nil, now), do: %{"action" => "ended", "at" => iso(now)}

  defp resolution_document(%{action: action, at: at}, _now),
    do: %{"action" => action, "at" => iso(at)}

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  # Each contact's record, its booking and its listen profiles' names, looked up once per read.
  defp context(org, mission, adapters) do
    contacts =
      adapters
      |> Enum.map(& &1.realized_contact_id)
      |> Enum.uniq()
      |> Enum.flat_map(fn id ->
        case ContactStore.fetch_realized(org, mission, id) do
          {:ok, %RealizedContact{} = contact} -> [{id, contact}]
          _missing -> []
        end
      end)
      |> Map.new()

    %{
      org: org,
      mission: mission,
      contacts: contacts,
      reservations: reservations(org, mission, Map.values(contacts))
    }
  end

  defp scheduled_contact_id(context, contact) do
    case Map.get(context.contacts, contact) do
      %RealizedContact{scheduled_contact_id: id} -> id
      nil -> nil
    end
  end

  defp profile_name(context, profile_id) do
    case ProfileStore.fetch_provider_profile(context.org, context.mission, profile_id) do
      {:ok, profile} -> (profile.metadata || %{})["display_name"]
      _missing -> nil
    end
  end

  defp reservation_id(_org, _mission, nil), do: nil

  defp reservation_id(org, mission, scheduled_id) do
    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.scheduled_contact_id == ^scheduled_id,
      select: row.provider_reservation_id,
      limit: 1
    )
    |> Repo.one()
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

  # The pass the contact realizes, from its booking (U47's pass label); nil fields without one.
  defp pass(context, contact) do
    case Map.get(context.reservations, scheduled_contact_id(context, contact)) do
      nil ->
        %{
          spacecraft_id: nil,
          provider_reservation_id: nil,
          ground_station_ref: nil,
          provider_id: nil,
          starts_at: nil,
          ends_at: nil
        }

      reservation ->
        %{
          spacecraft_id: reservation.spacecraft_id,
          provider_reservation_id: reservation.provider_reservation_id,
          ground_station_ref:
            Enum.find_value(
              [reservation.provider_confirmed_snapshot_document, reservation.request_document],
              &(is_map(&1) && &1["ground_station_ref"])
            ),
          provider_id: reservation.provider_id,
          starts_at: reservation.starts_at,
          ends_at: reservation.ends_at
        }
    end
  end
end
