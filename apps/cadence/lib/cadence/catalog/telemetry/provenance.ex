defmodule Cadence.Catalog.Telemetry.Provenance do
  @moduledoc """
  Provenance carried by canonical telemetry catalog definitions.
  """

  alias Cadence.Catalog.Telemetry.Normalize

  @type t :: %__MODULE__{
          artifact_id: binary() | nil,
          import_run_id: binary() | nil,
          importer_key: binary() | nil,
          source_ref: binary() | nil,
          source_path: [binary()],
          warnings: [binary()],
          lossy_mappings: [binary()],
          metadata: map()
        }

  defstruct [
    :artifact_id,
    :import_run_id,
    :importer_key,
    :source_ref,
    source_path: [],
    warnings: [],
    lossy_mappings: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      artifact_id: Normalize.get(attrs, :artifact_id),
      import_run_id: Normalize.get(attrs, :import_run_id),
      importer_key: Normalize.get(attrs, :importer_key),
      source_ref: Normalize.get(attrs, :source_ref),
      source_path: string_list(Normalize.get(attrs, :source_path, [])),
      warnings: string_list(Normalize.get(attrs, :warnings, [])),
      lossy_mappings: string_list(Normalize.get(attrs, :lossy_mappings, [])),
      metadata: Normalize.get(attrs, :metadata, %{})
    }
  end

  defp string_list(values) when is_list(values) do
    Enum.filter(values, &is_binary/1)
  end

  defp string_list(_other), do: []
end
