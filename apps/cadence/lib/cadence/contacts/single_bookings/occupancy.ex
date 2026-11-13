defmodule Cadence.Contacts.SingleBookings.Occupancy do
  @moduledoc """
  Single bookings as occupancy (L15, DECISIONS #78): the live reservations a search offer may
  overlap, and the fixed occupancy a planning run records so drafts and repairs plan around them.
  """

  import Ecto.Query

  alias Cadence.Comms.StationRefs
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @live ~w(requesting pending confirmed active unknown)

  @doc """
  Live reservations overlapping `[from, to)`, as occupancy: `[%{reservation_id, spacecraft_id,
  spacecraft_name, antenna_ref, station_code, starts_at, ends_at, off_plan}]`. `only_off_plan:
  true` keeps single bookings only (the planner's fixed occupancy, DECISIONS #78).
  """
  def list(organization_id, mission_id, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    rows =
      ProviderReservationRow
      |> where(
        [r],
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.lifecycle_state in ^@live and r.starts_at < ^to and r.ends_at > ^from
      )
      |> then(fn query ->
        if Keyword.get(opts, :only_off_plan, false),
          do: where(query, [r], is_nil(r.contact_plan_id)),
          else: query
      end)
      |> select([r], %{
        provider_reservation_id: r.provider_reservation_id,
        spacecraft_id: r.spacecraft_id,
        metadata: r.metadata,
        starts_at: r.starts_at,
        ends_at: r.ends_at,
        contact_plan_id: r.contact_plan_id
      })
      |> Repo.all()

    names = names(organization_id, mission_id, rows)
    stations = if rows == [], do: %{}, else: StationRefs.index(organization_id, mission_id)

    Enum.map(rows, fn r ->
      metadata = JsonDocument.unwrap_value(r.metadata) || %{}

      %{
        reservation_id: r.provider_reservation_id,
        spacecraft_id: r.spacecraft_id,
        spacecraft_name: Map.get(names, r.spacecraft_id),
        antenna_ref: metadata["antenna_or_service_pool_ref"],
        station_code: StationRefs.resolve(metadata["ground_station_ref"], stations).code,
        starts_at: r.starts_at,
        ends_at: r.ends_at,
        off_plan: is_nil(r.contact_plan_id)
      }
    end)
  end

  @doc """
  The live single bookings in a planning run's horizon (`attrs` with `horizon_start` and
  `horizon_end`, DateTime or ISO 8601), as the run records them (`input_document["occupied"]`,
  DECISIONS #78). Whoever starts a run supplies this, so the planner reads it from the run without
  depending on Contacts.
  """
  def document(organization_id, mission_id, attrs) do
    with {:ok, from} <- horizon(attrs, :horizon_start),
         {:ok, to} <- horizon(attrs, :horizon_end) do
      organization_id
      |> list(mission_id, from, to, only_off_plan: true)
      |> Enum.map(fn o ->
        %{
          "reservation_id" => o.reservation_id,
          "spacecraft_id" => o.spacecraft_id,
          "antenna_ref" => o.antenna_ref,
          "starts_at" => DateTime.to_iso8601(o.starts_at),
          "ends_at" => DateTime.to_iso8601(o.ends_at)
        }
      end)
    else
      _no_horizon -> []
    end
  end

  defp horizon(attrs, key) do
    case Map.get(attrs, key, Map.get(attrs, Atom.to_string(key))) do
      %DateTime{} = at ->
        {:ok, at}

      text when is_binary(text) ->
        case DateTime.from_iso8601(text) do
          {:ok, at, _offset} -> {:ok, at}
          _invalid -> :error
        end

      _missing ->
        :error
    end
  end

  @doc """
  The first occupancy `slot` (`%{spacecraft_id, antenna_ref, starts_at, ends_at}`) overlaps: the
  same spacecraft, else another spacecraft on the same antenna. `nil` when free.
  """
  def overlap(occupancy, slot) do
    overlapping =
      Enum.filter(occupancy, fn o ->
        DateTime.before?(o.starts_at, slot.ends_at) and DateTime.after?(o.ends_at, slot.starts_at)
      end)

    same_spacecraft = Enum.find(overlapping, &(&1.spacecraft_id == slot.spacecraft_id))

    same_antenna =
      Enum.find(overlapping, fn o ->
        is_binary(slot.antenna_ref) and o.antenna_ref == slot.antenna_ref and
          o.spacecraft_id != slot.spacecraft_id
      end)

    case {same_spacecraft, same_antenna} do
      {%{} = o, _} -> overlap_view(o, "same_spacecraft")
      {nil, %{} = o} -> overlap_view(o, "same_antenna")
      {nil, nil} -> nil
    end
  end

  defp overlap_view(o, reason),
    do: %{
      reservation_id: o.reservation_id,
      spacecraft: %{id: o.spacecraft_id, name: o.spacecraft_name},
      station_code: o.station_code,
      starts_at: o.starts_at,
      reason: reason
    }

  defp names(_organization_id, _mission_id, []), do: %{}

  defp names(organization_id, mission_id, rows) do
    ids = rows |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()
    {:ok, found} = SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids)
    Map.new(found, fn {id, sc} -> {id, sc.display_name} end)
  end

  @doc "`[%{provider_reservation_id, spacecraft_id, starts_at}]` overlapping `[from, to)`."
  @spec live(binary(), binary(), DateTime.t(), DateTime.t()) :: [map()]
  def live(organization_id, mission_id, %DateTime{} = from, %DateTime{} = to) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        is_nil(r.contact_plan_id) and r.lifecycle_state in ^@live and
        r.starts_at < ^to and r.ends_at > ^from
    )
    |> order_by([r], asc: r.starts_at, asc: r.provider_reservation_id)
    |> select([r], %{
      provider_reservation_id: r.provider_reservation_id,
      spacecraft_id: r.spacecraft_id,
      starts_at: r.starts_at
    })
    |> Repo.all()
  end

  def live(_organization_id, _mission_id, _from, _to), do: []
end
