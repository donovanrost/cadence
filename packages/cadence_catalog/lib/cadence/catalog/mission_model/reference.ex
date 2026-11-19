defmodule Cadence.Catalog.MissionModel.Reference do
  @moduledoc "Typed source or resolved reference between Mission Model declarations."

  alias Cadence.Catalog.MissionModel.{Canonical, Provenance}

  @type t :: %__MODULE__{
          expected_kind: atom(),
          source_ref: binary(),
          role: atom() | nil,
          resolved_id: binary() | nil,
          resolved_qualified_name: binary() | nil,
          required: boolean(),
          provenance: Provenance.t() | nil
        }

  # Stored models decode kinds and roles from strings. These are literals here so the atoms exist
  # whenever this module is loaded: `String.to_existing_atom` depended on whichever importer
  # happened to be loaded, and a fresh VM couldn't decode a `criteria` role (2026-11-12 outage).
  # The kinds are `Declaration.kinds/0` (a test keeps them equal).
  @kinds ~w(space_system unit parameter_type parameter container calibrator algorithm
    monitoring_policy command_argument_type command_argument command_encoding command
    command_constraint command_verifier stream service extension)a
  @roles ~w(argument base calibrator command condition criteria effect encoding entry input
    output parameter type unit)a
  @kinds_by_name Map.new(@kinds, &{Atom.to_string(&1), &1})
  @roles_by_name Map.new(@roles, &{Atom.to_string(&1), &1})

  @doc "The declaration kinds a reference may expect."
  def kinds, do: @kinds

  @doc "The roles a reference may play."
  def roles, do: @roles

  @enforce_keys [:expected_kind, :source_ref]
  defstruct @enforce_keys ++
              [:role, :resolved_id, :resolved_qualified_name, :provenance, required: true]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      expected_kind: attrs |> value(:expected_kind) |> normalize_kind(),
      source_ref: value(attrs, :source_ref),
      role: normalize_role(value(attrs, :role)),
      resolved_id: value(attrs, :resolved_id),
      resolved_qualified_name: value(attrs, :resolved_qualified_name),
      required: value(attrs, :required, true),
      provenance: attrs |> value(:provenance) |> Provenance.new()
    }
  end

  @doc "The versioned hash basis (#166): every field; provenance through its own basis."
  @spec hash_basis(t()) :: Canonical.basis()
  def hash_basis(%__MODULE__{} = reference) do
    {:mission_model_reference, 1,
     %{
       expected_kind: reference.expected_kind,
       source_ref: reference.source_ref,
       role: reference.role,
       resolved_id: reference.resolved_id,
       resolved_qualified_name: reference.resolved_qualified_name,
       required: reference.required,
       provenance: Provenance.hash_basis(reference.provenance)
     }}
  end

  defp normalize_kind(kind) when is_atom(kind), do: kind
  defp normalize_kind(kind) when is_binary(kind), do: known!(@kinds_by_name, kind, "kind")

  defp normalize_role(nil), do: nil
  defp normalize_role(role) when is_atom(role), do: role
  defp normalize_role(role) when is_binary(role), do: known!(@roles_by_name, role, "role")

  defp known!(names, name, what) do
    case Map.fetch(names, name) do
      {:ok, atom} -> atom
      :error -> raise ArgumentError, "unknown mission model reference #{what}: #{inspect(name)}"
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
