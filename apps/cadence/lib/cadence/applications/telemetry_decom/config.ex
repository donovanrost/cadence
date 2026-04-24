defmodule Cadence.Applications.TelemetryDecom.Config do
  @moduledoc """
  Per-spacecraft Telemetry Decom configuration.

  Tracks which catalog revision and APIDs a spacecraft's Telemetry Decom
  application handles, along with the version of the mission binding set last
  materialized from this configuration. The binding set / activation
  bookkeeping is not exposed as a user-facing concept — it is recorded here so
  the UI can show whether the current configuration matches what is live.
  """

  @type t :: %__MODULE__{
          spacecraft_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          catalog_revision_id: binary(),
          handled_apids: [non_neg_integer()],
          source_endpoint_id: binary(),
          enabled: boolean(),
          applied_binding_set_id: binary() | nil,
          applied_binding_set_version: pos_integer() | nil,
          applied_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :spacecraft_id,
    :organization_id,
    :mission_id,
    :catalog_revision_id,
    :source_endpoint_id,
    :applied_binding_set_id,
    :applied_binding_set_version,
    :applied_at,
    enabled: true,
    handled_apids: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      spacecraft_id: Map.fetch!(attrs, :spacecraft_id),
      organization_id: Map.get(attrs, :organization_id),
      mission_id: Map.fetch!(attrs, :mission_id),
      catalog_revision_id: Map.fetch!(attrs, :catalog_revision_id),
      handled_apids: Map.get(attrs, :handled_apids, []),
      source_endpoint_id: Map.fetch!(attrs, :source_endpoint_id),
      enabled: Map.get(attrs, :enabled, true),
      applied_binding_set_id: Map.get(attrs, :applied_binding_set_id),
      applied_binding_set_version: Map.get(attrs, :applied_binding_set_version),
      applied_at: Map.get(attrs, :applied_at),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
