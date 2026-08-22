defmodule Cadence.Catalog.ImportResult do
  @moduledoc """
  Persistence-independent result produced by one catalog importer.
  """

  alias Cadence.Catalog.{Bundle, Diagnostic}

  @type t :: %__MODULE__{
          bundle: Bundle.t(),
          imported_definition_count: non_neg_integer(),
          diagnostics: [Diagnostic.t()],
          metadata: map()
        }

  defstruct bundle: %Bundle{}, imported_definition_count: 0, diagnostics: [], metadata: %{}

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      bundle: build_bundle(attrs),
      imported_definition_count: Map.get(attrs, :imported_definition_count, 0),
      diagnostics: Map.get(attrs, :diagnostics, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp build_bundle(%{bundle: %Bundle{} = bundle}), do: bundle
  defp build_bundle(%{"bundle" => %Bundle{} = bundle}), do: bundle

  defp build_bundle(attrs) do
    Bundle.new(%{
      declaration_layers:
        Map.get(attrs, :declaration_layers, Map.get(attrs, "declaration_layers", []))
    })
  end
end
