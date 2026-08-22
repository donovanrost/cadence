defmodule Cadence.Contacts.LinkAssignment do
  @moduledoc """
  Spacecraft-specific application of a mission-owned link template.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type lifecycle_state :: :active | :deleted

  @type t :: %__MODULE__{
          link_assignment_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          lifecycle_state: lifecycle_state(),
          spacecraft_id: binary(),
          source_endpoint_ref: binary(),
          path_template_id: binary(),
          path_template_version: pos_integer(),
          direction: :uplink | :downlink,
          selection_role: :selected | :candidate | :contributing,
          provider_path_ref: binary() | nil,
          provider_profile_refs: [map()],
          transport_profile_refs: [map()],
          metadata: map()
        }

  defstruct [
    :link_assignment_id,
    :organization_id,
    :mission_id,
    :lifecycle_state,
    :spacecraft_id,
    :source_endpoint_ref,
    :path_template_id,
    :path_template_version,
    :direction,
    :selection_role,
    :provider_path_ref,
    provider_profile_refs: [],
    transport_profile_refs: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      link_assignment_id:
        Map.get(
          attrs,
          :link_assignment_id,
          Map.get(attrs, "link_assignment_id", Ids.new("link_assignment"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      spacecraft_id: Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id")),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      path_template_id: Map.get(attrs, :path_template_id, Map.get(attrs, "path_template_id")),
      path_template_version:
        Map.get(attrs, :path_template_version, Map.get(attrs, "path_template_version", 1)),
      direction:
        Map.get(attrs, :direction, Map.get(attrs, "direction"))
        |> KnownAtom.direction!(),
      selection_role:
        Map.get(attrs, :selection_role, Map.get(attrs, "selection_role", :selected))
        |> KnownAtom.selection_role!(),
      provider_path_ref: Map.get(attrs, :provider_path_ref, Map.get(attrs, "provider_path_ref")),
      provider_profile_refs:
        attrs
        |> Map.get(:provider_profile_refs, Map.get(attrs, "provider_profile_refs", []))
        |> Enum.map(&normalize_profile_ref(&1, "provider_profile_id")),
      transport_profile_refs:
        attrs
        |> Map.get(:transport_profile_refs, Map.get(attrs, "transport_profile_refs", []))
        |> Enum.map(&normalize_profile_ref(&1, "transport_profile_id")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_lifecycle_state(lifecycle_state),
    do: KnownAtom.versioned_resource_lifecycle_state!(lifecycle_state)

  defp normalize_profile_ref(%{} = ref, id_key) do
    %{
      id_key => Map.get(ref, id_key) || Map.get(ref, to_string(id_key)),
      "version" => Map.get(ref, "version") || Map.get(ref, :version) || 1
    }
  end
end
