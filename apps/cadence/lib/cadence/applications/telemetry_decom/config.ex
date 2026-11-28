defmodule Cadence.Applications.TelemetryDecom.Config do
  @moduledoc """
  Per-spacecraft Telemetry Decom configuration.

  Projects the saved configuration and the completed generation that applied it,
  when the spacecraft's assignment is in that generation's fleet.
  """

  @type t :: %__MODULE__{
          spacecraft_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          configuration_version: pos_integer(),
          catalog_revision_id: binary(),
          handled_apids: [non_neg_integer()],
          source_endpoint_id: binary() | nil,
          enabled: boolean(),
          applied_binding_set_id: binary() | nil,
          applied_binding_set_version: pos_integer() | nil,
          applied_generation: pos_integer() | nil,
          applied_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :spacecraft_id,
    :organization_id,
    :mission_id,
    :configuration_version,
    :catalog_revision_id,
    :source_endpoint_id,
    :applied_binding_set_id,
    :applied_binding_set_version,
    :applied_generation,
    :applied_at,
    :updated_at,
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
      configuration_version: Map.get(attrs, :configuration_version, 1),
      catalog_revision_id: Map.fetch!(attrs, :catalog_revision_id),
      handled_apids: Map.get(attrs, :handled_apids, []),
      source_endpoint_id: Map.fetch!(attrs, :source_endpoint_id),
      enabled: Map.get(attrs, :enabled, true),
      applied_binding_set_id: Map.get(attrs, :applied_binding_set_id),
      applied_binding_set_version: Map.get(attrs, :applied_binding_set_version),
      applied_generation: Map.get(attrs, :applied_generation),
      applied_at: Map.get(attrs, :applied_at),
      updated_at: Map.get(attrs, :updated_at),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
