defmodule Cadence.Applications.PacketBindingConfiguration do
  @moduledoc "Versioned desired and applied packet bindings for one installed application input."

  alias Cadence.Applications.PacketBinding
  alias Cadence.Ids

  @type t :: %__MODULE__{
          packet_binding_configuration_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          spacecraft_id: binary() | nil,
          application_installation_id: binary(),
          application_key: binary(),
          application_version: pos_integer(),
          capability_family_key: atom(),
          input_id: binary(),
          input_version: pos_integer(),
          configuration_version: pos_integer(),
          enabled: boolean(),
          applied_binding_set_id: binary() | nil,
          applied_binding_set_version: pos_integer() | nil,
          applied_at: DateTime.t() | nil,
          bindings: [PacketBinding.t()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          metadata: map()
        }

  @enforce_keys [
    :packet_binding_configuration_id,
    :organization_id,
    :mission_id,
    :application_installation_id,
    :application_key,
    :application_version,
    :capability_family_key,
    :input_id,
    :input_version,
    :configuration_version
  ]

  defstruct [
    :packet_binding_configuration_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :application_installation_id,
    :application_key,
    :application_version,
    :capability_family_key,
    :input_id,
    :input_version,
    :configuration_version,
    :applied_binding_set_id,
    :applied_binding_set_version,
    :applied_at,
    :inserted_at,
    :updated_at,
    enabled: true,
    bindings: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    bindings =
      attrs
      |> value(:bindings, [])
      |> Enum.map(fn
        %PacketBinding{} = binding -> binding
        binding_attrs -> PacketBinding.new(binding_attrs)
      end)

    %__MODULE__{
      packet_binding_configuration_id:
        value(attrs, :packet_binding_configuration_id) ||
          Ids.new("packet_binding_configuration"),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      spacecraft_id: value(attrs, :spacecraft_id),
      application_installation_id: required(attrs, :application_installation_id),
      application_key: required(attrs, :application_key),
      application_version: required(attrs, :application_version),
      capability_family_key:
        attrs |> required(:capability_family_key) |> normalize_capability_family_key(),
      input_id: required(attrs, :input_id),
      input_version: required(attrs, :input_version),
      configuration_version: value(attrs, :configuration_version, 1),
      enabled: value(attrs, :enabled, true),
      applied_binding_set_id: value(attrs, :applied_binding_set_id),
      applied_binding_set_version: value(attrs, :applied_binding_set_version),
      applied_at: value(attrs, :applied_at),
      bindings: bindings,
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at),
      metadata: value(attrs, :metadata, %{})
    }
  end

  defp normalize_capability_family_key(value) when is_atom(value), do: value

  defp normalize_capability_family_key(value) when is_binary(value),
    do: String.to_existing_atom(value)

  defp normalize_capability_family_key(value), do: value

  defp required(attrs, key), do: value(attrs, key) || raise(KeyError, key: key, term: attrs)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
