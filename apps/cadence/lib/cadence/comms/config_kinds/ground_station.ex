defmodule Cadence.Comms.ConfigKinds.GroundStation do
  @moduledoc """
  Change-set kind for mission ground stations.

  Document: `%{"display_name", "code", "provider", "region", "metadata", "latitude_deg",
  "longitude_deg", "height_m", "elevation_mask_deg"}`. Delete archives the station. Ground
  stations are setup context only (not yet linked to routing), so applying a change has no
  runtime effect.

  The location (#890) is the mission's own, WGS84 geodetic: latitude and longitude come together
  or not at all, and height defaults to 0 m when they are given. The elevation mask defaults to
  5°. A provider's reported location is kept apart (`Cadence.Comms.StationLocations`) and is
  never part of this document.
  """

  @behaviour Cadence.Platform.ConfigKind

  import Ecto.Query

  alias Cadence.Comms.{GroundStation, GroundStationRow, GroundStationStore, StationGeometry}
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Repo

  @fields ~w(display_name code provider region metadata latitude_deg longitude_deg height_m
             elevation_mask_deg)
  @default_mask_deg 5.0

  @impl true
  def kind, do: "ground_station"

  @impl true
  def id_prefix, do: "ground_station"

  @impl true
  def load(organization_id, mission_id, ids) do
    GroundStationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.ground_station_id in ^ids and row.lifecycle_state == "active"
    )
    |> Repo.all()
    |> Map.new(fn row ->
      station = GroundStationRow.to_domain(row)
      {station.ground_station_id, document(station)}
    end)
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    document =
      document
      |> Map.put_new("metadata", %{})
      |> blank_code()
      |> geometry_defaults()

    errors =
      F.only(document, @fields) ++
        F.text(document, "display_name", 1..200, required: true, label: "Name") ++
        code_errors(document) ++
        F.text(document, "provider", 1..200, label: "Provider") ++
        F.text(document, "region", 1..200, label: "Region") ++
        F.map(document, "metadata") ++
        geometry_errors(document)

    F.result(document |> floats(), errors)
  end

  def normalize(_action, _id, _document), do: {:error, [F.error("", "Enter the station details")]}

  @impl true
  # Archiving: refused while anything still uses it (director 11-16, ux U82), at stage
  # (stage_check/4) and again here, which re-runs at preview and apply. The uses come through the
  # :config_users adapter (Cadence.Control.ConfigUsers), so comms needs no edge to contacts.
  def validate(organization_id, mission_id, :delete, entity_id, previous, nil) do
    case uses(organization_id, mission_id, entity_id) do
      nil ->
        :ok

      uses ->
        entity = %{kind: "ground_station", id: entity_id, name: (previous || %{})["display_name"]}

        {:error,
         [
           ""
           |> F.error("This station is still in use, so it can't be archived.")
           |> Map.put(:in_use, %{entity: entity, uses: uses})
         ]}
    end
  end

  def validate(organization_id, mission_id, action, entity_id, previous, proposed) do
    with :ok <- code_kept(action, previous, proposed),
         do: code_free(organization_id, mission_id, entity_id, proposed)
  end

  # ux U25: Code is optional while none is stored; once set it can change but not be emptied
  # (pass titles and filters show it).
  defp code_kept(:update, %{"code" => old}, proposed) when is_binary(old) and old != "" do
    if is_nil(Map.get(proposed, "code")),
      do:
        {:error,
         [
           F.error(
             "code",
             "#{old} is already used in pass titles and filters, so it can be changed but not removed."
           )
         ]},
      else: :ok
  end

  defp code_kept(_action, _previous, _proposed), do: :ok

  defp code_free(organization_id, mission_id, entity_id, %{"code" => code})
       when is_binary(code) do
    taken? =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id)
      |> Enum.any?(&(&1.code == code and &1.ground_station_id != entity_id))

    if taken?,
      do: {:error, [F.error("code", "#{code} is already used by another station")]},
      else: :ok
  end

  defp code_free(_organization_id, _mission_id, _entity_id, _proposed), do: :ok

  # Height and mask defaults; geometry numbers are stored as floats.
  defp geometry_defaults(document) do
    document =
      Map.update(document, "elevation_mask_deg", @default_mask_deg, &(&1 || @default_mask_deg))

    if is_nil(document["height_m"]) and not is_nil(document["latitude_deg"]),
      do: Map.put(document, "height_m", 0.0),
      else: Map.put_new(document, "height_m", nil)
  end

  defp floats(document) do
    Enum.reduce(~w(latitude_deg longitude_deg height_m elevation_mask_deg), document, fn key,
                                                                                         doc ->
      case doc[key] do
        value when is_integer(value) -> Map.put(doc, key, value * 1.0)
        _other -> Map.put_new(doc, key, nil)
      end
    end)
  end

  defp geometry_errors(document) do
    number(document, "latitude_deg", -90, 90, "Latitude", "−90 to 90°") ++
      number(document, "longitude_deg", -180, 180, "Longitude", "−180 to 180°") ++
      number(document, "height_m", -1000, 10_000, "Height", "−1,000 to 10,000 m") ++
      mask_errors(document["elevation_mask_deg"]) ++ paired(document)
  end

  defp number(document, key, min, max, label, range) do
    case document[key] do
      nil -> []
      value when is_number(value) and value >= min and value <= max -> []
      value when is_number(value) -> [F.error(key, "#{label} must be #{range}")]
      _other -> [F.error(key, "#{label} must be a number")]
    end
  end

  defp mask_errors(mask) when is_number(mask) and mask >= 0 and mask <= 89.9, do: []

  defp mask_errors(mask) when is_number(mask),
    do: [F.error("elevation_mask_deg", "Elevation mask must be 0 to 89.9°")]

  defp mask_errors(_mask), do: [F.error("elevation_mask_deg", "Elevation mask must be a number")]

  # Latitude and longitude come together; a height needs both.
  defp paired(document) do
    lat = document["latitude_deg"]
    lon = document["longitude_deg"]

    cond do
      is_nil(lat) and not is_nil(lon) ->
        [F.error("latitude_deg", "Enter the latitude too")]

      is_nil(lon) and not is_nil(lat) ->
        [F.error("longitude_deg", "Enter the longitude too")]

      is_nil(lat) and not is_nil(document["height_m"]) ->
        [F.error("height_m", "Enter the latitude and longitude too")]

      true ->
        []
    end
  end

  # A cleared field (empty or blank) means no code.
  defp blank_code(%{"code" => code} = document) when is_binary(code) do
    if String.trim(code) == "", do: Map.put(document, "code", nil), else: document
  end

  defp blank_code(document), do: document

  defp code_errors(%{"code" => code}) when is_binary(code) do
    if Regex.match?(~r/\A[A-Z0-9]{2,8}\z/, code),
      do: [],
      else: [F.error("code", "Use 2–8 capital letters or digits, like SVB")]
  end

  defp code_errors(%{"code" => nil}), do: []

  defp code_errors(%{"code" => _}),
    do: [F.error("code", "Use 2–8 capital letters or digits, like SVB")]

  defp code_errors(_document), do: []

  @impl true
  def stage_check(organization_id, mission_id, :delete, entity_id, deleting) do
    case uses(organization_id, mission_id, entity_id, deleting) do
      nil ->
        :ok

      uses ->
        {:error, {:in_use, %{entity: entity(organization_id, mission_id, entity_id), uses: uses}}}
    end
  end

  def stage_check(_organization_id, _mission_id, _action, _entity_id, _deleting), do: :ok

  defp entity(organization_id, mission_id, id) do
    name =
      case GroundStationStore.fetch_ground_station(organization_id, mission_id, id) do
        {:ok, station} -> station.display_name
        _gone -> nil
      end

    %{kind: "ground_station", id: id, name: name}
  end

  # nil when nothing uses it (or no adapter is configured).
  defp uses(organization_id, mission_id, station_id, deleting \\ MapSet.new()) do
    with users when users != nil <- Application.get_env(:cadence, :config_users),
         uses = users.station_uses(organization_id, mission_id, station_id, except: deleting),
         true <- users.in_use?(uses) do
      uses
    else
      _free -> nil
    end
  end

  @impl true
  def write(organization_id, mission_id, :create, id, nil, proposed, _options) do
    station =
      GroundStation.new(%{
        ground_station_id: id,
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: proposed["display_name"],
        code: proposed["code"],
        provider: proposed["provider"],
        region: proposed["region"],
        metadata: proposed["metadata"],
        location: location(proposed),
        elevation_mask_deg: proposed["elevation_mask_deg"]
      })

    if station.location,
      do: :ok = StationGeometry.stage_recompute(organization_id, mission_id, [id])

    stored(GroundStationStore.persist_ground_station(organization_id, station))
  end

  def write(organization_id, mission_id, :update, id, previous, proposed, _options) do
    if StationGeometry.changed?(previous, proposed),
      do: :ok = StationGeometry.stage_recompute(organization_id, mission_id, [id])

    attrs = %{
      display_name: proposed["display_name"],
      code: proposed["code"],
      provider: proposed["provider"],
      region: proposed["region"],
      metadata: proposed["metadata"],
      location: location(proposed),
      elevation_mask_deg: proposed["elevation_mask_deg"] || @default_mask_deg
    }

    stored(GroundStationStore.update_ground_station(organization_id, mission_id, id, attrs))
  end

  def write(organization_id, mission_id, :delete, id, _previous, nil, _options) do
    case GroundStationStore.archive_ground_station(organization_id, mission_id, id) do
      {:ok, _station} ->
        # Its passes go: the station run finds it archived.
        :ok = StationGeometry.stage_recompute(organization_id, mission_id, [id])
        {:ok, nil, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def summary(:create, nil, proposed), do: "Add ground station #{proposed["display_name"]}"
  def summary(:delete, previous, nil), do: "Archive ground station #{previous["display_name"]}"
  def summary(:update, previous, _proposed), do: "Edit ground station #{previous["display_name"]}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  defp stored({:ok, station}), do: {:ok, document(station), []}
  defp stored({:error, reason}), do: {:error, reason}

  defp document(%GroundStation{} = station) do
    location = station.location || %{}

    %{
      "display_name" => station.display_name,
      "code" => station.code,
      "provider" => station.provider,
      "region" => station.region,
      "metadata" => station.metadata || %{},
      "latitude_deg" => Map.get(location, :latitude_deg),
      "longitude_deg" => Map.get(location, :longitude_deg),
      "height_m" => Map.get(location, :height_m),
      "elevation_mask_deg" => station.elevation_mask_deg
    }
  end

  defp location(%{"latitude_deg" => lat, "longitude_deg" => lon, "height_m" => height})
       when is_number(lat) and is_number(lon) and is_number(height),
       do: %{latitude_deg: lat * 1.0, longitude_deg: lon * 1.0, height_m: height * 1.0}

  defp location(_document), do: nil
end
