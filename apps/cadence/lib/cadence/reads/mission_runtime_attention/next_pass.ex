defmodule Cadence.Reads.MissionRuntimeAttention.NextPass do
  @moduledoc """
  The `mission_runtime` item's `next_pass` (U91): the mission's pass in progress (its window open
  now), else the next one starting within 2 h, else nil, so the operator sees which pass the
  runtime failure costs.

  `%{contact_id, spacecraft_id, spacecraft_name, station: %{name, code} | nil, starts_at,
  ends_at, in_progress, started}`: `started` is true only when the pass's contact actually
  started (its realized contact got past `:defined`); in progress but not started is a pass
  that couldn't start (U45 `no_runtime_spec`). Station and spacecraft come from the event log's
  contact facts (`Reads.EventContacts`), so every surface names them the same way.
  """

  alias Cadence.Contacts
  alias Cadence.Contacts.{OverlappingContacts, RealizedContact, ScheduledContact}
  alias Cadence.Reads.EventContacts
  alias Cadence.SpacecraftStore

  @horizon_s 2 * 3600

  @spec for_mission(binary(), binary(), DateTime.t()) :: map() | nil
  def for_mission(org, mission, %DateTime{} = now) do
    org
    |> OverlappingContacts.list(mission, now, DateTime.add(now, @horizon_s, :second))
    |> pick(now)
    |> describe(org, mission, now)
  rescue
    # The runtime item must still show if this read fails; it just names no pass.
    _exception -> nil
  end

  defp pick(contacts, now) do
    Enum.find(contacts, &in_progress?(&1, now)) || Enum.find(contacts, &upcoming?(&1, now))
  end

  defp describe(nil, _org, _mission, _now), do: nil

  defp describe(%ScheduledContact{} = contact, org, mission, now) do
    facts =
      org
      |> EventContacts.contact_facts(mission, [contact.scheduled_contact_id])
      |> Map.get(contact.scheduled_contact_id, %{})

    spacecraft_id = Map.get(facts, :spacecraft_id)

    %{
      contact_id: contact.scheduled_contact_id,
      spacecraft_id: spacecraft_id,
      spacecraft_name: spacecraft_name(org, mission, spacecraft_id),
      station: Map.get(facts, :station),
      starts_at: contact.starts_at,
      ends_at: contact.ends_at,
      in_progress: in_progress?(contact, now),
      started: started?(org, mission, contact)
    }
  end

  defp in_progress?(%ScheduledContact{starts_at: starts_at, ends_at: ends_at}, now) do
    DateTime.compare(starts_at, now) != :gt and
      (is_nil(ends_at) or DateTime.compare(ends_at, now) == :gt)
  end

  defp upcoming?(%ScheduledContact{starts_at: starts_at}, now),
    do: DateTime.compare(starts_at, now) == :gt

  defp started?(_org, _mission, %ScheduledContact{realized_contact_id: nil}), do: false

  defp started?(org, mission, %ScheduledContact{realized_contact_id: id}) do
    case Contacts.fetch_realized_contact(org, mission, id) do
      {:ok, %RealizedContact{lifecycle_state: state}} -> state != :defined
      _missing -> false
    end
  end

  defp spacecraft_name(_org, _mission, nil), do: nil

  defp spacecraft_name(org, mission, spacecraft_id) do
    case SpacecraftStore.fetch_spacecraft(org, mission, spacecraft_id) do
      {:ok, %{display_name: name}} when is_binary(name) and name != "" -> name
      _missing -> nil
    end
  end
end
