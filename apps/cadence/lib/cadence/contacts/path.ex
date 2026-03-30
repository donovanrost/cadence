defmodule Cadence.Contacts.Path do
  @moduledoc """
  Directional realized-contact path runtime definition.
  """

  alias Cadence.Contacts.{KnownAtom, ProviderBinding, TransportBinding}
  alias Cadence.Ids

  @type direction :: :uplink | :downlink
  @type selection_role :: :selected | :candidate | :contributing

  @type t :: %__MODULE__{
          path_id: binary(),
          direction: direction(),
          selection_role: selection_role(),
          source_endpoint_ref: binary() | nil,
          provider_path_ref: binary() | nil,
          provider_bindings: [ProviderBinding.t()],
          transport_bindings: [TransportBinding.t()],
          metadata: map()
        }

  defstruct [
    :path_id,
    :direction,
    :selection_role,
    :source_endpoint_ref,
    :provider_path_ref,
    provider_bindings: [],
    transport_bindings: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
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
      provider_bindings:
        attrs
        |> Map.get(:provider_bindings, Map.get(attrs, "provider_bindings", []))
        |> Enum.map(&build_provider_binding/1),
      transport_bindings:
        attrs
        |> Map.get(:transport_bindings, Map.get(attrs, "transport_bindings", []))
        |> Enum.map(&build_transport_binding/1),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp build_provider_binding(%ProviderBinding{} = provider_binding), do: provider_binding
  defp build_provider_binding(attrs) when is_map(attrs), do: ProviderBinding.new(attrs)

  defp build_transport_binding(%TransportBinding{} = transport_binding), do: transport_binding
  defp build_transport_binding(attrs) when is_map(attrs), do: TransportBinding.new(attrs)

  defp normalize_direction(direction), do: KnownAtom.direction!(direction)
  defp normalize_selection_role(selection_role), do: KnownAtom.selection_role!(selection_role)
end
