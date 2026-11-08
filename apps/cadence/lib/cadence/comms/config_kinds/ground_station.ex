defmodule Cadence.Comms.ConfigKinds.GroundStation do
  @moduledoc """
  Change-set kind for mission ground stations.

  Document: `%{"display_name", "provider", "region", "metadata"}`. Delete archives the station.
  Ground stations are setup context only (not yet linked to routing), so applying a change has
  no runtime effect.
  """

  @behaviour Cadence.Platform.ConfigKind

  import Ecto.Query

  alias Cadence.Comms.{GroundStation, GroundStationRow, GroundStationStore}
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Repo

  @fields ~w(display_name provider region metadata)

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
    document = Map.put_new(document, "metadata", %{})

    errors =
      F.only(document, @fields) ++
        F.text(document, "display_name", 1..200, required: true, label: "Name") ++
        F.text(document, "provider", 1..200, label: "Provider") ++
        F.text(document, "region", 1..200, label: "Region") ++
        F.map(document, "metadata")

    F.result(document, errors)
  end

  def normalize(_action, _id, _document), do: {:error, [F.error("", "Enter the station details")]}

  @impl true
  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  @impl true
  def write(organization_id, mission_id, :create, id, nil, proposed, _options) do
    station =
      GroundStation.new(%{
        ground_station_id: id,
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: proposed["display_name"],
        provider: proposed["provider"],
        region: proposed["region"],
        metadata: proposed["metadata"]
      })

    stored(GroundStationStore.persist_ground_station(organization_id, station))
  end

  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    attrs = %{
      display_name: proposed["display_name"],
      provider: proposed["provider"],
      region: proposed["region"],
      metadata: proposed["metadata"]
    }

    stored(GroundStationStore.update_ground_station(organization_id, mission_id, id, attrs))
  end

  def write(organization_id, mission_id, :delete, id, _previous, nil, _options) do
    case GroundStationStore.archive_ground_station(organization_id, mission_id, id) do
      {:ok, _station} -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
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
    %{
      "display_name" => station.display_name,
      "provider" => station.provider,
      "region" => station.region,
      "metadata" => station.metadata || %{}
    }
  end
end
