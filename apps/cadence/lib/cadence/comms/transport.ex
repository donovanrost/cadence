defmodule Cadence.Comms.Transport do
  @moduledoc """
  Mission-owned durable byte-moving capability.

  A Transport is setup state. It describes an external capability Cadence can
  use to move bytes; it does not represent an active connection or contact.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :active | :archived
  @type transport_kind :: :tcp_socket
  @type direction_capability :: :inbound | :outbound | :bidirectional
  @type adapter_key :: :tcp_socket
  @type origin :: :direct | :provider_managed

  @type t :: %__MODULE__{
          transport_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          display_name: binary(),
          origin: origin(),
          transport_kind: transport_kind(),
          direction_capability: direction_capability(),
          adapter_key: adapter_key(),
          configuration: map(),
          mission_provider_id: binary() | nil,
          mission_provider_version: pos_integer() | nil,
          service_profile_ref: map() | nil,
          delivery_profile_ref: map() | nil,
          provider_configuration_snapshot: map(),
          materialized_provider_profile_id: binary() | nil,
          metadata: map()
        }

  defstruct [
    :transport_id,
    :organization_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :display_name,
    :origin,
    :transport_kind,
    :direction_capability,
    :adapter_key,
    :mission_provider_id,
    :mission_provider_version,
    :service_profile_ref,
    :delivery_profile_ref,
    :materialized_provider_profile_id,
    configuration: %{},
    provider_configuration_snapshot: %{},
    metadata: %{}
  ]

  @transport_kinds [:tcp_socket]
  @direction_capabilities [:inbound, :outbound, :bidirectional]
  @adapter_keys [:tcp_socket]
  @origins [:direct, :provider_managed]
  @lifecycle_states [:active, :archived]

  @spec transport_kinds() :: [transport_kind()]
  def transport_kinds, do: @transport_kinds

  @spec direction_capabilities() :: [direction_capability()]
  def direction_capabilities, do: @direction_capabilities

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    kind =
      attrs
      |> Map.get(:transport_kind, Map.get(attrs, "transport_kind", :tcp_socket))
      |> normalize_atom(@transport_kinds, :transport_kind)

    %__MODULE__{
      transport_id:
        Map.get(attrs, :transport_id, Map.get(attrs, "transport_id", Ids.new("transport"))),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      version: Map.get(attrs, :version, Map.get(attrs, "version", 1)),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_atom(@lifecycle_states, :lifecycle_state),
      display_name: Map.fetch!(attrs, :display_name),
      origin:
        attrs
        |> Map.get(:origin, Map.get(attrs, "origin", :direct))
        |> normalize_atom(@origins, :origin),
      transport_kind: kind,
      direction_capability:
        attrs
        |> Map.get(:direction_capability, Map.get(attrs, "direction_capability", :bidirectional))
        |> normalize_atom(@direction_capabilities, :direction_capability),
      adapter_key:
        attrs
        |> Map.get(:adapter_key, Map.get(attrs, "adapter_key", default_adapter_key(kind)))
        |> normalize_atom(@adapter_keys, :adapter_key),
      configuration: Map.get(attrs, :configuration, Map.get(attrs, "configuration", %{})),
      mission_provider_id:
        Map.get(attrs, :mission_provider_id, Map.get(attrs, "mission_provider_id")),
      mission_provider_version:
        Map.get(attrs, :mission_provider_version, Map.get(attrs, "mission_provider_version")),
      service_profile_ref:
        Map.get(attrs, :service_profile_ref, Map.get(attrs, "service_profile_ref")),
      delivery_profile_ref:
        Map.get(attrs, :delivery_profile_ref, Map.get(attrs, "delivery_profile_ref")),
      provider_configuration_snapshot:
        Map.get(
          attrs,
          :provider_configuration_snapshot,
          Map.get(attrs, "provider_configuration_snapshot", %{})
        ),
      materialized_provider_profile_id:
        Map.get(
          attrs,
          :materialized_provider_profile_id,
          Map.get(attrs, "materialized_provider_profile_id")
        ),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp default_adapter_key(:tcp_socket), do: :tcp_socket

  defp normalize_atom(value, allowed, field) when is_atom(value) do
    if value in allowed do
      value
    else
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize_atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize_atom(value, _allowed, field) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end
end
