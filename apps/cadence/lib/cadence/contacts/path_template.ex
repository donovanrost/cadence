defmodule Cadence.Contacts.PathTemplate do
  @moduledoc """
  Mission-owned reusable path definition that references provider and transport
  profiles.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type direction :: :uplink | :downlink
  @type selection_role :: :selected | :candidate | :contributing
  @type lifecycle_state :: :active | :deleted

  @type t :: %__MODULE__{
          path_template_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          path_id: binary(),
          direction: direction(),
          selection_role: selection_role(),
          source_endpoint_ref: binary() | nil,
          provider_path_ref: binary() | nil,
          provider_profile_ids: [binary()],
          provider_profile_refs: [map()],
          transport_profile_ids: [binary()],
          transport_profile_refs: [map()],
          metadata: map()
        }

  defstruct [
    :path_template_id,
    :organization_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :path_id,
    :direction,
    :selection_role,
    :source_endpoint_ref,
    :provider_path_ref,
    provider_profile_ids: [],
    provider_profile_refs: [],
    transport_profile_ids: [],
    transport_profile_refs: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      path_template_id:
        Map.get(
          attrs,
          :path_template_id,
          Map.get(attrs, "path_template_id", Ids.new("path_template"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      version: Map.get(attrs, :version, Map.get(attrs, "version", 1)),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      path_id: Map.get(attrs, :path_id, Map.get(attrs, "path_id", Ids.new("path"))),
      direction:
        Map.get(attrs, :direction, Map.get(attrs, "direction"))
        |> normalize_direction(),
      selection_role:
        Map.get(attrs, :selection_role, Map.get(attrs, "selection_role", :candidate))
        |> normalize_selection_role(),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      provider_path_ref: Map.get(attrs, :provider_path_ref, Map.get(attrs, "provider_path_ref")),
      provider_profile_ids:
        Map.get(attrs, :provider_profile_ids, Map.get(attrs, "provider_profile_ids", [])),
      provider_profile_refs:
        attrs
        |> Map.get(:provider_profile_refs, Map.get(attrs, "provider_profile_refs", []))
        |> Enum.map(&normalize_profile_ref(&1, "provider_profile_id")),
      transport_profile_ids:
        Map.get(attrs, :transport_profile_ids, Map.get(attrs, "transport_profile_ids", [])),
      transport_profile_refs:
        attrs
        |> Map.get(:transport_profile_refs, Map.get(attrs, "transport_profile_refs", []))
        |> Enum.map(&normalize_profile_ref(&1, "transport_profile_id")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_direction(direction), do: KnownAtom.direction!(direction)
  defp normalize_selection_role(selection_role), do: KnownAtom.selection_role!(selection_role)

  defp normalize_lifecycle_state(lifecycle_state),
    do: KnownAtom.versioned_resource_lifecycle_state!(lifecycle_state)

  defp normalize_profile_ref(%{} = ref, id_key) do
    %{
      id_key => Map.get(ref, id_key) || Map.get(ref, to_string(id_key)),
      "version" => Map.get(ref, "version") || Map.get(ref, :version) || 1
    }
  end
end
