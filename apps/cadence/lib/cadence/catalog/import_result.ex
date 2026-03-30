defmodule Cadence.Catalog.ImportResult do
  @moduledoc """
  Result of one completed catalog import run.
  """

  alias Cadence.Catalog.Diagnostic

  @type t :: %__MODULE__{
          snapshot_id: binary() | nil,
          imported_definition_count: non_neg_integer(),
          diagnostics: [Diagnostic.t()],
          result_document: map()
        }

  defstruct snapshot_id: nil, imported_definition_count: 0, diagnostics: [], result_document: %{}

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      snapshot_id: Map.get(attrs, :snapshot_id, Map.get(attrs, "snapshot_id")),
      imported_definition_count: Map.get(attrs, :imported_definition_count, 0),
      diagnostics: Map.get(attrs, :diagnostics, []),
      result_document: Map.get(attrs, :result_document, %{})
    }
  end
end
