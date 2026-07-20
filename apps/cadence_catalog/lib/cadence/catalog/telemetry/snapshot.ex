defmodule Cadence.Catalog.Telemetry.Snapshot do
  @moduledoc """
  Immutable canonical telemetry catalog snapshot derived from one import run.
  """

  alias Cadence.Catalog.Telemetry.{
    CalibrationAlgorithm,
    Normalize,
    Packet,
    Point,
    Provenance,
    Type,
    Unit
  }

  alias Cadence.Catalog.Ids

  @type t :: %__MODULE__{
          snapshot_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          artifact_id: binary(),
          import_run_id: binary(),
          importer_key: binary(),
          snapshot_name: binary(),
          snapshot_version: binary() | nil,
          description: binary() | nil,
          published_at: DateTime.t() | nil,
          superseded_at: DateTime.t() | nil,
          units: [Unit.t()],
          calibration_algorithms: [CalibrationAlgorithm.t()],
          types: [Type.t()],
          points: [Point.t()],
          packets: [Packet.t()],
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
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
    :provenance,
    units: [],
    calibration_algorithms: [],
    types: [],
    points: [],
    packets: [],
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      snapshot_id: Normalize.get(attrs, :snapshot_id, Ids.new("telemetry_snapshot")),
      organization_id: Normalize.get(attrs, :organization_id),
      mission_id: Normalize.fetch!(attrs, :mission_id),
      artifact_id: Normalize.fetch!(attrs, :artifact_id),
      import_run_id: Normalize.fetch!(attrs, :import_run_id),
      importer_key: Normalize.fetch!(attrs, :importer_key),
      snapshot_name: Normalize.fetch!(attrs, :snapshot_name),
      snapshot_version: Normalize.get(attrs, :snapshot_version),
      description: Normalize.get(attrs, :description),
      published_at: Normalize.get(attrs, :published_at),
      superseded_at: Normalize.get(attrs, :superseded_at),
      units: Normalize.nested_list(attrs, :units, Unit),
      calibration_algorithms:
        Normalize.nested_list(attrs, :calibration_algorithms, CalibrationAlgorithm),
      types: Normalize.nested_list(attrs, :types, Type),
      points: Normalize.nested_list(attrs, :points, Point),
      packets: Normalize.nested_list(attrs, :packets, Packet),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end
end
