defmodule Cadence.Catalog.TelemetrySnapshotRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.Telemetry.Snapshot
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:snapshot_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "catalog_telemetry_snapshots" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:artifact_id, :string)
    field(:import_run_id, :string)
    field(:importer_key, :string)
    field(:snapshot_name, :string)
    field(:snapshot_version, :string)
    field(:description, :string)
    field(:published_at, :utc_datetime_usec)
    field(:superseded_at, :utc_datetime_usec)
    field(:packet_count, :integer)
    field(:point_count, :integer)
    field(:type_count, :integer)
    field(:unit_count, :integer)
    field(:calibration_algorithm_count, :integer)
    field(:snapshot_document, :map)

    timestamps()
  end

  @required_fields [
    :snapshot_id,
    :mission_id,
    :artifact_id,
    :import_run_id,
    :importer_key,
    :snapshot_name,
    :packet_count,
    :point_count,
    :type_count,
    :unit_count,
    :calibration_algorithm_count,
    :snapshot_document
  ]

  @spec changeset(Snapshot.t()) :: Ecto.Changeset.t()
  def changeset(%Snapshot{} = snapshot) do
    changeset(%__MODULE__{}, snapshot)
  end

  @spec changeset(struct(), Snapshot.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %Snapshot{} = snapshot) do
    row
    |> cast(domain_attrs(snapshot), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Snapshot.t()
  def to_domain(%__MODULE__{} = row) do
    row.snapshot_document
    |> JsonDocument.unwrap_value()
    |> Map.merge(%{
      "snapshot_id" => row.snapshot_id,
      "organization_id" => row.organization_id,
      "mission_id" => row.mission_id,
      "artifact_id" => row.artifact_id,
      "import_run_id" => row.import_run_id,
      "importer_key" => row.importer_key,
      "snapshot_name" => row.snapshot_name,
      "snapshot_version" => row.snapshot_version,
      "description" => row.description,
      "published_at" => row.published_at,
      "superseded_at" => row.superseded_at
    })
    |> Snapshot.new()
  end

  defp domain_attrs(%Snapshot{} = snapshot) do
    %{
      snapshot_id: snapshot.snapshot_id,
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      artifact_id: snapshot.artifact_id,
      import_run_id: snapshot.import_run_id,
      importer_key: snapshot.importer_key,
      snapshot_name: snapshot.snapshot_name,
      snapshot_version: snapshot.snapshot_version,
      description: snapshot.description,
      published_at: snapshot.published_at,
      superseded_at: snapshot.superseded_at,
      packet_count: length(snapshot.packets),
      point_count: length(snapshot.points),
      type_count: length(snapshot.types),
      unit_count: length(snapshot.units),
      calibration_algorithm_count: length(snapshot.calibration_algorithms),
      snapshot_document: JsonDocument.wrap_value(snapshot_document_attrs(snapshot))
    }
  end

  defp all_fields do
    [
      :snapshot_id,
      :organization_id,
      :mission_id,
      :artifact_id,
      :import_run_id,
      :importer_key,
      :snapshot_name,
      :snapshot_version,
      :description,
      :published_at,
      :superseded_at,
      :packet_count,
      :point_count,
      :type_count,
      :unit_count,
      :calibration_algorithm_count,
      :snapshot_document
    ]
  end

  defp snapshot_document_attrs(%Snapshot{} = snapshot) do
    snapshot
    |> JsonDocument.encode()
    |> normalize_snapshot_document()
  end

  defp normalize_snapshot_document(document) when is_map(document) do
    document
    |> Map.update("types", [], fn items -> Enum.map(items, &normalize_type_document/1) end)
    |> Map.update("points", [], fn items -> Enum.map(items, &normalize_point_document/1) end)
    |> Map.update("packets", [], fn items -> Enum.map(items, &normalize_packet_document/1) end)
  end

  defp normalize_snapshot_document(other), do: other

  defp normalize_type_document(document) when is_map(document) do
    rename_key(document, "default_calibration_algorithm_id", "default_calibration_algorithm")
  end

  defp normalize_type_document(other), do: other

  defp normalize_point_document(document) when is_map(document) do
    document
    |> rename_key("type_id", "type_ref")
    |> rename_key("unit_id", "unit_ref")
  end

  defp normalize_point_document(other), do: other

  defp normalize_packet_document(document) when is_map(document) do
    Map.update(document, "entries", [], fn items ->
      Enum.map(items, &normalize_packet_entry_document/1)
    end)
  end

  defp normalize_packet_document(other), do: other

  defp normalize_packet_entry_document(document) when is_map(document) do
    document
    |> rename_key("point_id", "point_ref")
    |> rename_key("nested_packet_id", "nested_packet_ref")
  end

  defp normalize_packet_entry_document(other), do: other

  defp rename_key(document, from_key, to_key)
       when is_map(document) and is_binary(from_key) and is_binary(to_key) do
    if Map.has_key?(document, to_key) do
      document
    else
      case Map.fetch(document, from_key) do
        {:ok, value} -> document |> Map.put(to_key, value) |> Map.delete(from_key)
        :error -> document
      end
    end
  end
end
