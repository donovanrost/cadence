defmodule Cadence.Contacts.ScidMismatch do
  @moduledoc """
  The frame-SCID cross-check on the contact record (DECISIONS #102). On a path whose one
  spacecraft's SCID is known, a TM frame with another SCID is refused before reassembly (its bytes
  stay in the journal and raw evidence). At settle the contact's journal consumers' tallies become
  `metadata["settlement"]["scid_mismatch"]`, one entry per path that checked a frame, written
  only when some path refused one:

      %{"path_id", "provider_binding_id", "ground_station_ref", "spacecraft_id", "expected_scid",
        "frames" (refused), "frames_total" (passed the integrity checks), "scids" (observed,
        sorted, at most 8), "scid_count" (distinct observed, uncapped)}

  A path that refused nothing still has its entry (`frames` 0): "most" is over all of the
  contact's frames. `most?/1` is the ONE definition of "most" (lead): more than half the
  contact's integrity-checked TM frames refused. It decides both the operational event
  (`contact_scid_mismatch`, one per contact) and the Now item (`ScidMismatchAttention`).
  """

  require Logger

  alias Cadence.Contacts.RealizedContact
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  @max_scids 8

  @doc "Settlement entries from the consumers' tallies; [] when no path refused a frame."
  @spec settlement_entries([map()], binary() | nil) :: [map()]
  def settlement_entries(checks, ground_station_ref) do
    if Enum.any?(checks, &(refused(&1) > 0)),
      do:
        checks
        |> Enum.map(&entry(&1, ground_station_ref))
        |> Enum.sort_by(&{-&1["frames"], &1["path_id"]}),
      else: []
  end

  @doc "The contact's settlement entries (none before #102, or with nothing refused)."
  @spec entries(RealizedContact.t()) :: [map()]
  def entries(%RealizedContact{metadata: metadata}),
    do: get_in(metadata || %{}, ["settlement", "scid_mismatch"]) || []

  @doc "Whether MORE than half of the contact's integrity-checked TM frames were refused."
  @spec most?([map()]) :: boolean()
  def most?(entries) do
    {refused, total} =
      Enum.reduce(entries, {0, 0}, fn entry, {refused, total} ->
        {refused + (entry["frames"] || 0), total + (entry["frames_total"] || 0)}
      end)

    total > 0 and refused * 2 > total
  end

  @doc """
  Persists the contact's `contact_scid_mismatch` event when `most?/1` holds. Its id is the
  contact's, so a re-settle upserts the same row: at most one per contact.
  """
  @spec record_event(RealizedContact.t(), [map()], DateTime.t()) ::
          {:ok, Event.t() | nil} | {:error, term()}
  def record_event(%RealizedContact{} = contact, entries, %DateTime{} = now) do
    if most?(entries),
      do: OperationalEvents.persist_event(event(contact, entries, now)),
      else: {:ok, nil}
  rescue
    # The settle is already recorded; an event that can't be built or stored mustn't undo it.
    error ->
      Logger.error(
        "contact_scid_mismatch event not recorded: #{Exception.message(error)}",
        mission_id: contact.mission_id,
        realized_contact_id: contact.realized_contact_id
      )

      {:error, {:contact_scid_mismatch_event_failed, Exception.message(error)}}
  end

  @doc "The contact's `contact_scid_mismatch` event (warning; Timeline)."
  @spec event(RealizedContact.t(), [map()], DateTime.t()) :: Event.t()
  def event(%RealizedContact{} = contact, entries, %DateTime{} = now) do
    id = contact.realized_contact_id
    started_at = contact.realized_at || contact.initial_time
    payload = payload(contact, entries, started_at)

    Event.new(%{
      event_id: "operational_event:contact_scid_mismatch:#{id}",
      organization_id: contact.organization_id,
      mission_id: contact.mission_id,
      occurred_at: now,
      recorded_at: now,
      effective_at: started_at,
      category: :contact,
      kind: :contact_scid_mismatch,
      severity: :warning,
      actor: %{kind: :system},
      subject: %{kind: :contact, id: id},
      scope: %{
        contact_id: id,
        realized_contact_id: id,
        spacecraft_id: spacecraft_id(entries),
        source_endpoint_refs: contact.source_endpoint_refs
      },
      # No source record: the contact's own interval event holds (realized_contact, id) in the
      # one-event-per-source-record index; this one correlates to the contact instead.
      causality: %{correlation_id: id},
      payload: payload,
      current: payload
    })
  end

  defp payload(contact, entries, started_at) do
    scids = entries |> Enum.flat_map(&(&1["scids"] || [])) |> Enum.uniq() |> Enum.sort()

    %{
      realized_contact_id: contact.realized_contact_id,
      spacecraft_id: spacecraft_id(entries),
      contact_started_at: started_at && DateTime.to_iso8601(started_at),
      ground_station_ref: (contact.metadata || %{})["ground_station_ref"],
      expected_scid: entries |> List.first(%{}) |> Map.get("expected_scid"),
      frames: Enum.sum(Enum.map(entries, &(&1["frames"] || 0))),
      frames_total: Enum.sum(Enum.map(entries, &(&1["frames_total"] || 0))),
      scids: Enum.take(scids, @max_scids),
      # A lower bound when a path's list was capped: the largest per-path distinct count.
      scid_count: Enum.max([length(scids) | Enum.map(entries, &(&1["scid_count"] || 0))])
    }
  end

  defp spacecraft_id(entries), do: Enum.find_value(entries, & &1["spacecraft_id"])

  defp entry(check, ground_station_ref) do
    scids = check.refused |> Map.keys() |> Enum.sort()

    %{
      "path_id" => check.path_id,
      "provider_binding_id" => check.provider_binding_id,
      "ground_station_ref" => ground_station_ref,
      "spacecraft_id" => Map.get(check, :spacecraft_id),
      "expected_scid" => check.expected_scid,
      "frames" => refused(check),
      "frames_total" => check.frames,
      "scids" => Enum.take(scids, @max_scids),
      "scid_count" => length(scids)
    }
  end

  defp refused(%{refused: refused}), do: refused |> Map.values() |> Enum.sum()
end
