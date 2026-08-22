defmodule Cadence.Catalog.MissionModel.Reference do
  @moduledoc "Typed source or resolved reference between Mission Model declarations."

  alias Cadence.Catalog.MissionModel.Provenance

  @type t :: %__MODULE__{
          expected_kind: atom(),
          source_ref: binary(),
          role: atom() | nil,
          resolved_id: binary() | nil,
          resolved_qualified_name: binary() | nil,
          required: boolean(),
          provenance: Provenance.t() | nil
        }

  @enforce_keys [:expected_kind, :source_ref]
  defstruct @enforce_keys ++
              [:role, :resolved_id, :resolved_qualified_name, :provenance, required: true]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      expected_kind: attrs |> value(:expected_kind) |> normalize_kind(),
      source_ref: value(attrs, :source_ref),
      role: normalize_optional_atom(value(attrs, :role)),
      resolved_id: value(attrs, :resolved_id),
      resolved_qualified_name: value(attrs, :resolved_qualified_name),
      required: value(attrs, :required, true),
      provenance: attrs |> value(:provenance) |> Provenance.new()
    }
  end

  defp normalize_kind(kind) when is_atom(kind), do: kind
  defp normalize_kind(kind) when is_binary(kind), do: String.to_existing_atom(kind)

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value) when is_atom(value), do: value
  defp normalize_optional_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
