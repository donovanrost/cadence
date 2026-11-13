defmodule Cadence.Reads.OffPlanBookingEvents do
  @moduledoc """
  Off-plan bookings as mission timeline entries (L15, DECISIONS #78): a `contact` event "Booked
  outside a plan by Mira K.: EARENDIL-312 · SVA 03:10Z" with the booker as actor and the note as
  the event's `detail`. Reservations aren't projected into the mission-events table, so
  `Cadence.Reads.MissionTimeline` merges these in when asked (`off_plan_bookings: true`).
  """

  alias Cadence.Contacts.ReservationActivity
  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.Passes

  # Off-plan bookings are rare; each one reads its pass row (names, station).
  @limit 50

  @spec entries(binary(), binary(), keyword()) :: [Entry.t()]
  def entries(organization_id, mission_id, opts \\ []) do
    organization_id
    |> ReservationActivity.off_plan(
      mission_id,
      Keyword.get(opts, :from_occurred_at),
      Keyword.get(opts, :to_occurred_at),
      @limit
    )
    |> Enum.flat_map(fn id ->
      case Passes.fetch(organization_id, mission_id, id) do
        {:ok, %{off_plan: %{} = off_plan} = pass} -> [entry(mission_id, pass, off_plan)]
        _gone -> []
      end
    end)
  end

  @doc "The operator sentence: who booked what, where and when it starts."
  @spec sentence(Entry.t(), binary()) :: binary()
  def sentence(%Entry{metadata: metadata}, by) do
    where =
      [metadata["spacecraft_name"], station_time(metadata)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" · ")

    "Booked outside a plan#{by}: #{where}"
  end

  @doc "The event's `detail`: the booker's note."
  @spec detail(Entry.t()) :: binary() | nil
  def detail(%Entry{metadata: metadata}), do: metadata["note"]

  defp entry(mission_id, pass, off_plan) do
    Entry.new(%{
      mission_id: mission_id,
      source_record_kind: :off_plan_booking,
      source_record_id: pass.id,
      occurred_at: booked_at(off_plan.booked_at) || pass.starts_at,
      category: :transport,
      kind: :contact_booked_off_plan,
      severity: :info,
      title: "Booked outside a plan",
      summary: off_plan.note,
      spacecraft_id: pass.spacecraft_id,
      subject_kind: :scheduled_contact,
      subject_id: pass.id,
      actor: actor(off_plan.booked_by),
      metadata: %{
        "spacecraft_name" => pass.spacecraft && pass.spacecraft[:name],
        "station_code" => pass.station && (pass.station[:code] || pass.station[:ref]),
        "starts_at" => pass.starts_at && DateTime.to_iso8601(pass.starts_at),
        "note" => off_plan.note,
        "reservation_id" => pass.id
      }
    })
  end

  defp station_time(%{"station_code" => code, "starts_at" => starts_at}) do
    time =
      case starts_at && DateTime.from_iso8601(starts_at) do
        {:ok, at, _offset} -> Calendar.strftime(at, "%H:%MZ")
        _unknown -> nil
      end

    [code, time] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp booked_at(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp booked_at(_none), do: nil

  defp actor(%{kind: kind, id: id}) when is_binary(id),
    do: %{"kind" => kind || "user", "id" => id}

  defp actor(_none), do: %{}
end
