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

  @fields ~w(display_name code provider region metadata)

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
        code_errors(document) ++
        F.text(document, "provider", 1..200, label: "Provider") ++
        F.text(document, "region", 1..200, label: "Region") ++
        F.map(document, "metadata")

    F.result(document, errors)
  end

  def normalize(_action, _id, _document), do: {:error, [F.error("", "Enter the station details")]}

  @impl true
  # Archiving: refused while anything still uses it (director 11-16, ux U82), at stage
  # (stage_check/4) and again here, which re-runs at preview and apply. The uses come through the
  # :config_users adapter (Cadence.Control.ConfigUsers), so comms needs no edge to contacts.
  def validate(organization_id, mission_id, :delete, entity_id, _previous, nil) do
    case uses(organization_id, mission_id, entity_id) do
      nil ->
        :ok

      uses ->
        {:error,
         [
           ""
           |> F.error("This station is still in use, so it can't be archived.")
           |> Map.put(:in_use, uses)
         ]}
    end
  end

  def validate(organization_id, mission_id, _action, entity_id, _previous, %{"code" => code})
      when is_binary(code) do
    taken? =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id)
      |> Enum.any?(&(&1.code == code and &1.ground_station_id != entity_id))

    if taken?,
      do: {:error, [F.error("code", "#{code} is already used by another station")]},
      else: :ok
  end

  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

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
      nil -> :ok
      uses -> {:error, {:in_use, uses}}
    end
  end

  def stage_check(_organization_id, _mission_id, _action, _entity_id, _deleting), do: :ok

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
        metadata: proposed["metadata"]
      })

    stored(GroundStationStore.persist_ground_station(organization_id, station))
  end

  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    attrs = %{
      display_name: proposed["display_name"],
      code: proposed["code"],
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
      "code" => station.code,
      "provider" => station.provider,
      "region" => station.region,
      "metadata" => station.metadata || %{}
    }
  end
end
