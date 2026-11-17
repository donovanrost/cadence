defmodule Cadence.Contacts.ContactStartAttention do
  @moduledoc """
  The `contact_start` source of the mission attention read (ux U45): a scheduled pass whose
  runtime failed to start, so a lost pass is never silent (P9CS night, 11-14: four earlier passes
  were lost this way without a trace).

  Conflict `not_started` while the pass's window is open: Cadence retries by itself (`retry`
  `"automatic"`) on every reconcile and the moment the pass holding the station listener ends;
  the item resolves (`resolved_by` system, action `started`) when it starts. Conflict `missed`
  once the window ended without a start: it stays until an operator marks it as seen
  (`acknowledge/3`, action `acknowledged`).

  `reason` is one of `ContactStartFailure.reasons/0`; for `listener_in_use`, `holder` is the pass
  holding the listener; for `listen_endpoint_claimed`, `listen_port`, `transport_id` and
  `transport_name` say
  which transport's port another mission listens on (never which mission). Pass fields as
  `contact_settlement`'s.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{ContactStartFailure, ContactStore, ProfileStore, RealizedContact}
  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @source "contact_start"
  @epoch ~U[1970-01-01 00:00:00Z]

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    now = DateTime.utc_now()
    contacts = open_contacts(org, mission)
    holders = holders(org, mission, contacts)
    reservations = reservations(org, mission, contacts ++ Map.values(holders))

    contacts
    |> Enum.map(fn contact ->
      holder = Map.get(holders, contact.realized_contact_id)

      item(
        contact,
        Map.get(reservations, contact.scheduled_contact_id),
        holder,
        reservations,
        now
      )
    end)
    |> Enum.sort_by(&(&1.raised_at || @epoch), DateTime)
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission), do: %{open: length(open_contacts(org, mission)), acknowledged: 0}

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    for contact <- with_failure(org, mission),
        failure = contact.metadata["start_failure"],
        {action, at, by} <- resolution(failure),
        at != nil and DateTime.compare(at, since) != :lt do
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
  Marks a missed pass as seen (ux U45, as U37's lost telemetry). A pass still in its window is
  `{:error, :contact_start_not_missed}`; anything else is `{:error, :attention_item_not_found}`.
  """
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id) do
    now = DateTime.utc_now()

    with {:ok, actor} <- actor(scope, mission),
         {:ok, contact} <- fetch_open(scope.organization_id, mission, id),
         :ok <- missed(scope.organization_id, mission, contact, now),
         failure =
           Map.merge(contact.metadata["start_failure"], %{
             "acknowledged_at" => DateTime.to_iso8601(now),
             "acknowledged_by" => actor
           }),
         {:ok, updated} <-
           ContactStore.update_realized_lifecycle(contact, contact.lifecycle_state, %{
             "start_failure" => failure
           }) do
      ScopedReadUpdates.publish(:attention_changed, scope.organization_id, mission)
      reservations = reservations(scope.organization_id, mission, [updated])

      {:ok,
       updated
       |> item(Map.get(reservations, updated.scheduled_contact_id), nil, reservations, now)
       |> Map.merge(%{
         state: "resolved",
         acknowledged_by: actor,
         resolution: %{action: "acknowledged", actor: actor, at: now, note: nil}
       })}
    end
  end

  @doc "Not an operator action for this source."
  @spec resolve(Scope.t(), binary(), binary(), String.t()) :: {:error, :attention_item_not_found}
  def resolve(_scope, _mission, _id, _action), do: {:error, :attention_item_not_found}

  @doc "Not an operator action for this source: Cadence retries by itself."
  @spec retry(Scope.t(), binary(), binary()) :: {:error, :attention_item_not_found}
  def retry(_scope, _mission, _id), do: {:error, :attention_item_not_found}

  defp resolution(%{"started_at" => at}),
    do: [{"started", timestamp(at), %{"kind" => "system"}}]

  defp resolution(%{"acknowledged_at" => at, "acknowledged_by" => by}),
    do: [{"acknowledged", timestamp(at), by}]

  defp resolution(_failure), do: []

  # todo(authz): Cedar should decide who may mark a missed pass as seen (any operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp fetch_open(org, mission, id) do
    case ContactStore.fetch_realized(org, mission, id) do
      {:ok, %RealizedContact{} = contact} ->
        if open?(contact), do: {:ok, contact}, else: missing()

      _other ->
        missing()
    end
  end

  defp missing, do: {:error, :attention_item_not_found}

  defp missed(org, mission, contact, now) do
    reservation = Map.get(reservations(org, mission, [contact]), contact.scheduled_contact_id)

    if conflict(contact, reservation, now) == "missed",
      do: :ok,
      else: {:error, :contact_start_not_missed}
  end

  defp open?(%RealizedContact{} = contact) do
    case ContactStartFailure.open_failure(contact) do
      %{} = failure -> not Map.has_key?(failure, "acknowledged_at")
      nil -> false
    end
  end

  defp open_contacts(org, mission), do: org |> with_failure(mission) |> Enum.filter(&open?/1)

  defp with_failure(org, mission) do
    from(row in RealizedContactRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          fragment("? -> 'value' -> 'start_failure' IS NOT NULL", row.metadata)
    )
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  # For listener_in_use, the pass on the same provider binding that held the listener: the
  # running one, else the latest that realized before this one.
  defp holders(org, mission, contacts) do
    binding_ids =
      for contact <- contacts,
          %{"reason" => "listener_in_use", "provider_binding_id" => id} <- [
            contact.metadata["start_failure"]
          ],
          is_binary(id),
          into: MapSet.new(),
          do: id

    if MapSet.size(binding_ids) == 0 do
      %{}
    else
      candidates =
        from(row in RealizedContactRow,
          where:
            row.organization_id == ^org and row.mission_id == ^mission and
              row.lifecycle_state in ["active", "stopped", "completed"]
        )
        |> Repo.all()
        |> Enum.map(&RealizedContactRow.to_domain/1)

      for contact <- contacts,
          %{"provider_binding_id" => id} <- [contact.metadata["start_failure"]],
          holder = holder(contact, id, candidates),
          into: %{},
          do: {contact.realized_contact_id, holder}
    end
  end

  defp holder(contact, binding_id, candidates) do
    candidates
    |> Enum.filter(
      &(&1.realized_contact_id != contact.realized_contact_id and uses_binding?(&1, binding_id) and
          realized_before?(&1, contact))
    )
    |> Enum.max_by(&realized_key/1, fn -> nil end)
  end

  defp uses_binding?(%RealizedContact{paths: paths}, binding_id) do
    Enum.any?(paths || [], fn path ->
      Enum.any?(path_bindings(path), &(binding_value(&1) == binding_id))
    end)
  end

  defp path_bindings(%{provider_bindings: bindings}) when is_list(bindings), do: bindings
  defp path_bindings(%{"provider_bindings" => bindings}) when is_list(bindings), do: bindings
  defp path_bindings(_path), do: []

  defp binding_value(%{provider_binding_id: id}), do: id
  defp binding_value(%{"provider_binding_id" => id}), do: id
  defp binding_value(_binding), do: nil

  defp realized_before?(%RealizedContact{realized_at: a}, %RealizedContact{realized_at: b})
       when is_struct(a, DateTime) and is_struct(b, DateTime),
       do: DateTime.compare(a, b) != :gt

  defp realized_before?(_candidate, _contact), do: true

  defp realized_key(%RealizedContact{realized_at: %DateTime{} = at}),
    do: DateTime.to_unix(at, :microsecond)

  defp realized_key(_contact), do: 0

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

  defp item(%RealizedContact{} = contact, reservation, holder, reservations, now) do
    failure = contact.metadata["start_failure"] || %{}

    %{
      id: contact.realized_contact_id,
      source: @source,
      conflict: conflict(contact, reservation, now),
      state: "open",
      reason: failure["reason"],
      failure_message: failure["failure_message"],
      contact_id: contact.scheduled_contact_id,
      realized_contact_id: contact.realized_contact_id,
      provider_profile_id: contact.metadata["provider_profile_id"],
      provider_profile_name: profile_name(contact),
      # listen_endpoint_claimed (ux U81): the port another mission listens on, and whose it is.
      listen_port: failure["listen_port"],
      transport_id: failure["transport_id"],
      transport_name: failure["transport_name"],
      reason_detail: failure["reason_detail"],
      holder: holder_fields(holder, reservations),
      raised_at: timestamp(failure["first_failed_at"]),
      last_attempt_at: timestamp(failure["last_attempt_at"]),
      attempts: failure["attempts"] || 0,
      retry: "automatic",
      expires_at: nil,
      acknowledged_by: nil,
      resolution: nil
    }
    |> Map.merge(pass(reservation))
  end

  # The window comes from the booking, else the scheduled contact's own ends_at.
  defp conflict(contact, reservation, now) do
    ends_at = (reservation && reservation.ends_at) || scheduled_ends_at(contact)

    if ends_at && DateTime.compare(ends_at, now) != :gt, do: "missed", else: "not_started"
  end

  defp scheduled_ends_at(%RealizedContact{} = contact) do
    case ContactStore.fetch_scheduled(contact.mission_id, contact.scheduled_contact_id) do
      {:ok, scheduled} -> scheduled.ends_at
      _other -> nil
    end
  end

  defp profile_name(%RealizedContact{organization_id: org, mission_id: mission} = contact) do
    with id when is_binary(id) <- contact.metadata["provider_profile_id"],
         {:ok, profile} <- ProfileStore.fetch_provider_profile(org, mission, id) do
      (profile.metadata || %{})["display_name"]
    else
      _missing -> nil
    end
  end

  defp holder_fields(nil, _reservations), do: nil

  defp holder_fields(%RealizedContact{} = holder, reservations) do
    reservation = Map.get(reservations, holder.scheduled_contact_id)

    Map.merge(
      %{realized_contact_id: holder.realized_contact_id, contact_id: holder.scheduled_contact_id},
      reservation
      |> pass()
      |> Map.take([
        :spacecraft_id,
        :provider_reservation_id,
        :ground_station_ref,
        :starts_at,
        :ends_at
      ])
    )
  end

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
