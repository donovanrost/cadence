defmodule Cadence.Catalog.Telemetry.Point do
  @moduledoc """
  Canonical telemetry point definition, independent of packet layout.
  """

  alias Cadence.Catalog.Ids
  alias Cadence.Catalog.Telemetry.{Normalize, Provenance, Type, Unit}

  @type parameter_source :: :telemetry | :constant | :local

  @type significance :: :none | :watch | :warning | :distress | :critical | :severe

  @type t :: %__MODULE__{
          point_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          display_name: binary() | nil,
          description: binary() | nil,
          short_description: binary() | nil,
          type_id: binary(),
          unit_id: binary() | nil,
          parameter_source: parameter_source(),
          system_point: boolean(),
          persistence_samples: non_neg_integer() | nil,
          stale_timeout_ms: non_neg_integer() | nil,
          significance: significance(),
          record_to_archive: boolean(),
          record_rate_limit_hz: number() | nil,
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :point_id,
    :snapshot_id,
    :name,
    :display_name,
    :description,
    :short_description,
    :type_id,
    :unit_id,
    :persistence_samples,
    :stale_timeout_ms,
    :record_rate_limit_hz,
    :provenance,
    parameter_source: :telemetry,
    system_point: false,
    significance: :none,
    record_to_archive: true,
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      point_id: Normalize.get(attrs, :point_id, Ids.new("telemetry_point")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      display_name: Normalize.get(attrs, :display_name),
      description: Normalize.get(attrs, :description),
      short_description: Normalize.get(attrs, :short_description),
      type_id: type_ref(Normalize.fetch!(attrs, :type_ref)),
      unit_id: unit_ref(Normalize.get(attrs, :unit_ref)),
      parameter_source:
        Normalize.get(attrs, :parameter_source, :telemetry) |> normalize_parameter_source(),
      system_point: Normalize.get(attrs, :system_point, false),
      persistence_samples: Normalize.get(attrs, :persistence_samples),
      stale_timeout_ms: Normalize.get(attrs, :stale_timeout_ms),
      significance: Normalize.get(attrs, :significance, :none) |> normalize_significance(),
      record_to_archive: Normalize.get(attrs, :record_to_archive, true),
      record_rate_limit_hz: Normalize.get(attrs, :record_rate_limit_hz),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp type_ref(%Type{type_id: type_id}), do: type_id
  defp type_ref(type_id) when is_binary(type_id), do: type_id

  defp unit_ref(%Unit{unit_id: unit_id}), do: unit_id
  defp unit_ref(unit_id) when is_binary(unit_id), do: unit_id
  defp unit_ref(_other), do: nil

  defp normalize_parameter_source(:telemetry), do: :telemetry
  defp normalize_parameter_source("telemetry"), do: :telemetry
  defp normalize_parameter_source(:constant), do: :constant
  defp normalize_parameter_source("constant"), do: :constant
  defp normalize_parameter_source(:local), do: :local
  defp normalize_parameter_source("local"), do: :local
  defp normalize_parameter_source(_other), do: :telemetry

  defp normalize_significance(:none), do: :none
  defp normalize_significance("none"), do: :none
  defp normalize_significance(:watch), do: :watch
  defp normalize_significance("watch"), do: :watch
  defp normalize_significance(:warning), do: :warning
  defp normalize_significance("warning"), do: :warning
  defp normalize_significance(:distress), do: :distress
  defp normalize_significance("distress"), do: :distress
  defp normalize_significance(:critical), do: :critical
  defp normalize_significance("critical"), do: :critical
  defp normalize_significance(:severe), do: :severe
  defp normalize_significance("severe"), do: :severe
  defp normalize_significance(_other), do: :none
end
