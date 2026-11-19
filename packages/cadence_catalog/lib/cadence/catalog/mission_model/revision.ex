defmodule Cadence.Catalog.MissionModel.Revision do
  @moduledoc "Resolved immutable Mission Model semantic graph."

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Diagnostic, Reference, SpaceSystem}

  @type status :: :candidate | :approved | :rejected | :retired

  @type t :: %__MODULE__{
          revision_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          status: status(),
          compiler_version: binary(),
          layer_ids: [binary()],
          declarations: %{binary() => struct()},
          space_systems: %{binary() => struct()},
          edges: [map()],
          diagnostics: [Diagnostic.t()],
          content_sha256: binary(),
          metadata: map()
        }

  @enforce_keys [
    :revision_id,
    :mission_id,
    :status,
    :compiler_version,
    :layer_ids,
    :content_sha256
  ]
  defstruct @enforce_keys ++
              [
                :organization_id,
                declarations: %{},
                space_systems: %{},
                edges: [],
                diagnostics: [],
                metadata: %{}
              ]

  # Bump on any change to what `hash_basis/1` hashes.
  # `content_sha256` stays bare hex, not #166's "v<n>:" form: it is copied out as an identity into
  # activation manifests, runtime plans and command requests, whose readers check 64-hex. The
  # version is inside the hash, so no two bases can compare equal (#166 rule 4 as amended by domain 11-19).
  @basis_version 1

  @spec build(map()) :: t()
  def build(attrs) when is_map(attrs) do
    content = %{
      organization_id: Map.get(attrs, :organization_id),
      mission_id: Map.fetch!(attrs, :mission_id),
      compiler_version: Map.fetch!(attrs, :compiler_version),
      layer_ids: Map.fetch!(attrs, :layer_ids),
      declarations: Map.fetch!(attrs, :declarations),
      space_systems: Map.fetch!(attrs, :space_systems),
      edges: Map.fetch!(attrs, :edges)
    }

    basis = hash_basis(content)

    %__MODULE__{
      revision_id:
        Map.get(attrs, :revision_id, Canonical.basis_content_id("mission_model_revision", basis)),
      organization_id: content.organization_id,
      mission_id: content.mission_id,
      status: Map.get(attrs, :status, :candidate),
      compiler_version: content.compiler_version,
      layer_ids: content.layer_ids,
      declarations: content.declarations,
      space_systems: content.space_systems,
      edges: content.edges,
      diagnostics: Map.get(attrs, :diagnostics, []),
      content_sha256: Map.get(attrs, :content_sha256, Canonical.basis_sha256(basis)),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  # The revision id and content hash basis (#166, #119): the organization and mission (ids are a
  # global primary key, so content in two missions must not share one), the compiler version, the
  # layers IN ORDER, and the compiled graph. Provenance hashes without the artifact and the import
  # run (`Provenance.hash_basis/1`), so identical content imported again is the same revision.
  # Diagnostics and metadata are derived or per-compile and stay out.
  defp hash_basis(content) do
    {:mission_model_revision, @basis_version,
     %{
       organization_id: content.organization_id,
       mission_id: content.mission_id,
       compiler_version: content.compiler_version,
       layer_ids: content.layer_ids,
       declarations:
         Map.new(content.declarations, fn {id, d} -> {id, Declaration.hash_basis(d)} end),
       space_systems:
         Map.new(content.space_systems, fn {id, s} -> {id, SpaceSystem.hash_basis(s)} end),
       edges: content.edges
     }}
  end

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    declarations =
      attrs
      |> value(:declarations, %{})
      |> Map.new(fn {id, declaration} -> {id, build_declaration(declaration)} end)

    space_systems =
      attrs
      |> value(:space_systems, %{})
      |> Map.new(fn {id, system} -> {id, build_space_system(system)} end)

    %__MODULE__{
      revision_id: value(attrs, :revision_id),
      organization_id: value(attrs, :organization_id),
      mission_id: value(attrs, :mission_id),
      status: attrs |> value(:status) |> normalize_status(),
      compiler_version: value(attrs, :compiler_version),
      layer_ids: value(attrs, :layer_ids, []),
      declarations: declarations,
      space_systems: space_systems,
      edges: value(attrs, :edges, []) |> Enum.map(&atomize_edge/1),
      diagnostics: value(attrs, :diagnostics, []) |> Enum.map(&Diagnostic.new/1),
      content_sha256: value(attrs, :content_sha256),
      metadata: value(attrs, :metadata, %{})
    }
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{diagnostics: diagnostics}) do
    not Enum.any?(diagnostics, &Diagnostic.blocking?/1)
  end

  defp build_declaration(%Declaration{} = declaration), do: declaration

  defp build_declaration(attrs), do: Declaration.new(attrs)

  defp build_space_system(%SpaceSystem{} = system), do: system
  defp build_space_system(attrs), do: SpaceSystem.new(attrs)

  defp atomize_edge(edge) do
    %{
      from: value(edge, :from),
      to: value(edge, :to),
      role: edge |> value(:role) |> normalize_edge_role(),
      required: value(edge, :required, true)
    }
  end

  # Explicit lists, not the atom table (2026-11-12): an edge carries its reference's role, so a
  # fresh VM must decode `criteria` without an importer loaded.
  @statuses_by_name Map.new(~w(candidate approved rejected retired)a, &{Atom.to_string(&1), &1})
  @edge_roles_by_name Map.new(
                        [:algorithm_dependency | Reference.roles()],
                        &{Atom.to_string(&1), &1}
                      )

  defp normalize_status(status) when is_atom(status), do: status

  defp normalize_status(status) when is_binary(status),
    do: known!(@statuses_by_name, status, "status")

  defp normalize_edge_role(nil), do: nil
  defp normalize_edge_role(role) when is_atom(role), do: role

  defp normalize_edge_role(role) when is_binary(role),
    do: known!(@edge_roles_by_name, role, "edge role")

  defp known!(names, name, what) do
    case Map.fetch(names, name) do
      {:ok, atom} -> atom
      :error -> raise ArgumentError, "unknown mission model revision #{what}: #{inspect(name)}"
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
