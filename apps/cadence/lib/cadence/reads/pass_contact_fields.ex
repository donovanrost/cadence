defmodule Cadence.Reads.PassContactFields do
  @moduledoc """
  U55/U56 on pass rows (docs/apogee/api/contacts.md §Cancel or end a contact):

    * `contact_action`: `"cancel"` before the contact is live, `"end"` while it is, else nil;
    * `contact_ended`: nil, or `{kind: canceled | ended_early, cause, by {kind, id, name}, at,
      reason, reason_code}`. `cause` is `operator`, or the provider's (`provider_failed`,
      `provider_canceled`, `provider_rejected`, …) when Cadence canceled it because the
      reservation won't fly; then `reason` is the provider's own words and `reason_code` its code.

  `detail/4` adds the pass detail's `queued_commands` (the spacecraft's queued requests, those
  expiring before its next commandable contact, and that contact: corrected windows, canceled
  and uplink-dropped contacts skipped) and `window_moves` (the provider's moves, newest first), and U50's `second_connections_refused`.
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Commanding
  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.{ContactAction, ListenerRefusalAttention, OpenContacts, PassContacts}
  alias Cadence.Contacts.UplinkPasses
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Reads.{PassBooking, PassIncompleteAtEnd, PassScidMismatch, PassTelemetryStored}

  @terminal [:canceled, :completed, :expired]

  @spec annotate(binary(), binary(), [map()], DateTime.t()) :: [map()]
  def annotate(org, mission, rows, now) do
    facts =
      PassContacts.facts(
        org,
        mission,
        Enum.map(rows, & &1.scheduled_contact_id) |> Enum.reject(&is_nil/1)
      )

    people = people(org, Map.values(facts))

    Enum.map(rows, fn row ->
      fact = Map.get(facts, row.scheduled_contact_id)

      Map.merge(row, %{
        contact_action: action(fact, now),
        contact_ended: ended(fact, people)
      })
    end)
  end

  # #146 (#468): the people who ended these contacts, named only while active members of the
  # mission's organization: one lookup for the whole read, never an email.
  defp people(org, facts) do
    ids =
      for %{ending: %ContactAction{actor: %{} = actor}} <- facts,
          user?(actor),
          id = value(actor, "id") || value(actor, "user_id"),
          is_binary(id),
          uniq: true,
          do: id

    MemberNames.members(org, ids)
  end

  @spec detail(binary(), binary(), map(), DateTime.t()) :: map()
  def detail(org, mission, pass, now) do
    # A hand-started row (U78) is its realized contact; a booking finds the one it realized.
    realized =
      Map.get(pass, :realized_contact_id) ||
        realized_contact_id(org, mission, pass.scheduled_contact_id)

    %{
      queued_commands: queued(org, mission, pass, now),
      window_moves: PassContacts.window_moves(org, pass.scheduled_contact_id),
      second_connections_refused: second_connections(org, mission, realized),
      # ux U60: did this pass's data reach the store (domain's settle event).
      telemetry_stored: PassTelemetryStored.read(org, mission, realized, craft_name(pass)),
      # ux U67: bytes at the end that didn't form a complete frame or packet (domain's settlement).
      incomplete_at_end: PassIncompleteAtEnd.read(org, mission, realized),
      # ux U81 §2 (#102): frames refused for another SCID, per path (domain's settlement).
      scid_mismatch: PassScidMismatch.read(org, mission, realized)
    }
    |> Map.merge(PassBooking.names(org, mission, pass))
  end

  defp realized_contact_id(_org, _mission, nil), do: nil

  defp realized_contact_id(org, mission, scheduled_contact_id) do
    case OpenContacts.latest_for_scheduled(org, mission, scheduled_contact_id) do
      nil -> nil
      contact -> contact.realized_contact_id
    end
  end

  # U50: second connections the pass's listener refused while its own was up (Technical details).
  # nil when the pass has no realized contact or the live count was lost to a restart.
  defp second_connections(_org, _mission, nil), do: nil

  defp second_connections(org, mission, realized_contact_id),
    do: ListenerRefusalAttention.second_connections_refused(org, mission, realized_contact_id)

  defp craft_name(%{spacecraft: %{name: name}}) when is_binary(name), do: name
  defp craft_name(%{spacecraft: %{id: id}}) when is_binary(id), do: id
  defp craft_name(_pass), do: "a spacecraft"

  @doc "Which of cancel or end applies now (never both), or nil."
  @spec action(map() | nil, DateTime.t()) :: binary() | nil
  def action(nil, _now), do: nil
  def action(%{ending: %ContactAction{}}, _now), do: nil
  def action(%{state: state}, _now) when state in @terminal, do: nil
  def action(%{live?: true}, _now), do: "end"

  def action(%{ends_at: %DateTime{} = ends_at}, now),
    do: if(DateTime.compare(now, ends_at) == :lt, do: "cancel")

  def action(_fact, _now), do: nil

  @doc """
  How the contact ended, or nil. `by` names a person from `people` (active members of the
  mission's organization, #468); any other person reads id and name nil.
  """
  @spec ended(map() | nil, %{binary() => binary() | nil}) :: map() | nil
  def ended(%{ending: %ContactAction{} = action}, people) do
    metadata = action.metadata || %{}
    actor = action.actor || %{}
    cause = value(metadata, "cause") || if(user?(actor), do: "operator")
    provider? = is_binary(cause) and String.starts_with?(cause, "provider_")

    %{
      kind:
        if(action.action_kind == :realized_contact_ended_early,
          do: "ended_early",
          else: "canceled"
        ),
      cause: cause,
      by: by(actor, people),
      at: action.occurred_at,
      reason: if(provider?, do: value(metadata, "provider_reason"), else: action.reason),
      reason_code: value(metadata, "provider_reason_code")
    }
  end

  # No action record (lead 11-14): `at` from the lifecycle's cancel time when it has one;
  # `cause` and `by` stay null. Every new cancel or end writes an action, so this is legacy only.
  def ended(%{state: :canceled} = fact, _people),
    do: %{
      kind: "canceled",
      cause: nil,
      by: nil,
      at: Map.get(fact, :canceled_at),
      reason: nil,
      reason_code: nil
    }

  def ended(_fact, _people), do: nil

  defp by(actor, people) do
    kind = value(actor, "kind")
    id = value(actor, "id") || value(actor, "user_id")

    # Null rather than a half actor (lead 11-14).
    cond do
      is_nil(kind) or is_nil(id) -> nil
      kind == "user" -> person(id, people)
      true -> %{kind: kind, id: id, name: nil}
    end
  end

  defp user?(actor), do: value(actor, "kind") == "user"

  defp person(id, people) do
    case Map.fetch(people, id) do
      {:ok, name} -> %{kind: "user", id: id, name: name}
      :error -> %{kind: "user", id: nil, name: nil}
    end
  end

  # Stored metadata comes back with string keys; freshly built with atoms.
  @keys %{
    "cause" => :cause,
    "provider_reason" => :provider_reason,
    "provider_reason_code" => :provider_reason_code,
    "kind" => :kind,
    "id" => :id,
    "user_id" => :user_id
  }

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Map.fetch!(@keys, key))

  defp value(_map, _key), do: nil

  # The spacecraft's queued requests; how many expire before its next commandable contact.
  defp queued(org, mission, pass, now) do
    spacecraft_id = pass.spacecraft && pass.spacecraft.id

    case spacecraft_id do
      nil -> nil
      id -> queued_for(org, mission, id, after_pass(pass, now))
    end
  end

  defp queued_for(org, mission, spacecraft_id, after_at) do
    refs =
      for {ref, ^spacecraft_id} <- Groups.spacecraft_by_endpoint(org, mission), do: ref

    requests =
      Enum.flat_map(refs, fn ref ->
        Commanding.list_command_requests(org, mission,
          source_endpoint_ref: ref,
          lifecycle_state: :queued
        )
      end)

    next =
      org
      |> UplinkPasses.upcoming(mission, [spacecraft_id], after_at, 1)
      |> Map.get(spacecraft_id, [])
      |> List.first()

    %{
      count: length(requests),
      expiring_before_next: expiring(requests, next),
      next_contact: next && next_contact(org, mission, next)
    }
  end

  defp expiring(_requests, nil), do: nil

  defp expiring(requests, %{starts_at: starts_at}) do
    case for(
           %{expires_at: %DateTime{} = at} <- requests,
           DateTime.compare(at, starts_at) == :lt,
           do: at
         ) do
      [] -> nil
      times -> %{count: length(times), earliest_at: Enum.min(times, DateTime)}
    end
  end

  defp next_contact(org, mission, next) do
    %{
      station: StationRefs.resolve(next.ground_station_ref, StationRefs.index(org, mission)),
      starts_at: next.starts_at
    }
  end

  defp after_pass(%{ends_at: %DateTime{} = ends_at}, now),
    do: if(DateTime.compare(ends_at, now) == :gt, do: ends_at, else: now)

  defp after_pass(_pass, now), do: now
end
