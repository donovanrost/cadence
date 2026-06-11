defmodule Cadence.SpacecraftType do
  @moduledoc """
  Mission-owned, versioned bus profile shared across spacecraft of the same kind.

  A `SpacecraftType` is a control-plane template: it captures the stable
  bus-level interpretation contract (downlink/uplink data link protocols, frame
  parameters, packet protocol) and declares which platform applications run for
  spacecraft of this type with what defaults. It is **not** consulted on the
  data-plane hot path. The control plane reads it once when provisioning or
  reconfiguring a spacecraft's runtime pipeline.

  Operationally mutable state (current catalog revisions, claimed APIDs,
  per-spacecraft application config overrides) lives on `Cadence.Spacecraft`,
  not here.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :active | :deleted
  @type downlink_protocol :: :tm | :aos | :uslp
  @type uplink_protocol :: :tc | :uslp
  @type packet_protocol :: :space_packet
  @type application_key :: binary()

  @type t :: %__MODULE__{
          spacecraft_type_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          display_name: binary(),
          downlink_protocol: downlink_protocol(),
          uplink_protocol: uplink_protocol(),
          packet_protocol: packet_protocol(),
          frame_parameters: map(),
          applications: %{application_key() => map()},
          metadata: map()
        }

  defstruct [
    :spacecraft_type_id,
    :organization_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :display_name,
    :downlink_protocol,
    :uplink_protocol,
    :packet_protocol,
    frame_parameters: %{},
    applications: %{},
    metadata: %{}
  ]

  @downlink_protocols [:tm, :aos, :uslp]
  @uplink_protocols [:tc, :uslp]
  @packet_protocols [:space_packet]
  @lifecycle_states [:active, :deleted]

  @spec downlink_protocols() :: [downlink_protocol()]
  def downlink_protocols, do: @downlink_protocols

  @spec uplink_protocols() :: [uplink_protocol()]
  def uplink_protocols, do: @uplink_protocols

  @spec packet_protocols() :: [packet_protocol()]
  def packet_protocols, do: @packet_protocols

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      spacecraft_type_id:
        Map.get(
          attrs,
          :spacecraft_type_id,
          Map.get(attrs, "spacecraft_type_id", Ids.new("spacecraft_type"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      version: Map.get(attrs, :version, Map.get(attrs, "version", 1)),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_atom(@lifecycle_states, :lifecycle_state),
      display_name: Map.fetch!(attrs, :display_name),
      downlink_protocol:
        attrs
        |> Map.get(:downlink_protocol, Map.get(attrs, "downlink_protocol"))
        |> normalize_atom(@downlink_protocols, :downlink_protocol),
      uplink_protocol:
        attrs
        |> Map.get(:uplink_protocol, Map.get(attrs, "uplink_protocol"))
        |> normalize_atom(@uplink_protocols, :uplink_protocol),
      packet_protocol:
        attrs
        |> Map.get(:packet_protocol, Map.get(attrs, "packet_protocol", :space_packet))
        |> normalize_atom(@packet_protocols, :packet_protocol),
      frame_parameters:
        Map.get(attrs, :frame_parameters, Map.get(attrs, "frame_parameters", %{})),
      applications:
        normalize_applications(Map.get(attrs, :applications, Map.get(attrs, "applications", %{}))),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

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

  defp normalize_applications(applications) when is_map(applications) do
    Map.new(applications, fn {key, config} ->
      {to_application_key(key), normalize_application_config(config)}
    end)
  end

  defp to_application_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_application_key(key) when is_binary(key), do: key

  defp normalize_application_config(config) when is_map(config), do: config
  defp normalize_application_config(_), do: %{}
end
