defmodule Cadence.GroundNetworks.MissionProvider do
  @moduledoc "Mission-owned provider control-plane setup."

  alias Cadence.Ids

  @provider_types [:simulator]
  @client_keys [:simulator_http]
  @lifecycle_states [:active, :archived]

  @type provider_type :: :simulator
  @type client_key :: :simulator_http
  @type lifecycle_state :: :active | :archived

  @type t :: %__MODULE__{
          provider_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          display_name: binary(),
          provider_account_id: binary() | nil,
          provider_account_version: pos_integer() | nil,
          provider_account_grant_id: binary() | nil,
          provider_account_grant_version: pos_integer() | nil,
          provider_type: provider_type(),
          client_key: client_key(),
          base_url: binary(),
          credential_ref: binary(),
          environment_ref: binary(),
          capabilities_document: map(),
          inventory_sync_document: map(),
          last_validated_at: DateTime.t() | nil,
          last_synced_at: DateTime.t() | nil,
          delivery_policy_document: map(),
          spacecraft_mappings_document: map(),
          enabled_service_profile_refs: [map()],
          enabled_delivery_profile_refs: [map()],
          permitted_resource_refs: [binary()],
          preferred_transport_refs: [map()],
          scheduling_policy_document: map(),
          fallback_policy_document: map(),
          metadata: map()
        }

  defstruct [
    :provider_id,
    :organization_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :display_name,
    :provider_account_id,
    :provider_account_version,
    :provider_account_grant_id,
    :provider_account_grant_version,
    :provider_type,
    :client_key,
    :base_url,
    :credential_ref,
    :environment_ref,
    :last_validated_at,
    :last_synced_at,
    delivery_policy_document: %{},
    spacecraft_mappings_document: %{},
    enabled_service_profile_refs: [],
    enabled_delivery_profile_refs: [],
    permitted_resource_refs: [],
    preferred_transport_refs: [],
    scheduling_policy_document: %{},
    fallback_policy_document: %{},
    capabilities_document: %{},
    inventory_sync_document: %{},
    metadata: %{}
  ]

  @spec provider_types() :: [provider_type()]
  def provider_types, do: @provider_types

  @spec client_keys() :: [client_key()]
  def client_keys, do: @client_keys

  @spec client_for(provider_type()) :: client_key()
  def client_for(:simulator), do: :simulator_http

  @spec simulated?(t()) :: boolean()
  def simulated?(%__MODULE__{provider_type: :simulator}), do: true

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    provider_type = normalize_atom(value(attrs, :provider_type), @provider_types, :provider_type)

    %__MODULE__{
      provider_id: value(attrs, :provider_id, Ids.new("provider")),
      organization_id: value(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      version: value(attrs, :version, 1),
      lifecycle_state:
        attrs
        |> value(:lifecycle_state, :active)
        |> normalize_atom(@lifecycle_states, :lifecycle_state),
      display_name: required(attrs, :display_name),
      provider_account_id: value(attrs, :provider_account_id),
      provider_account_version: value(attrs, :provider_account_version),
      provider_account_grant_id: value(attrs, :provider_account_grant_id),
      provider_account_grant_version: value(attrs, :provider_account_grant_version),
      provider_type: provider_type,
      client_key:
        attrs
        |> value(:client_key, client_for(provider_type))
        |> normalize_atom(@client_keys, :client_key),
      base_url: required(attrs, :base_url),
      credential_ref: required(attrs, :credential_ref),
      environment_ref: required(attrs, :environment_ref),
      capabilities_document: value(attrs, :capabilities_document, %{}),
      inventory_sync_document: value(attrs, :inventory_sync_document, %{}),
      last_validated_at: value(attrs, :last_validated_at),
      last_synced_at: value(attrs, :last_synced_at),
      delivery_policy_document: value(attrs, :delivery_policy_document, %{}),
      spacecraft_mappings_document: value(attrs, :spacecraft_mappings_document, %{}),
      enabled_service_profile_refs: value(attrs, :enabled_service_profile_refs, []),
      enabled_delivery_profile_refs: value(attrs, :enabled_delivery_profile_refs, []),
      permitted_resource_refs: value(attrs, :permitted_resource_refs, []),
      preferred_transport_refs: value(attrs, :preferred_transport_refs, []),
      scheduling_policy_document: value(attrs, :scheduling_policy_document, %{}),
      fallback_policy_document: value(attrs, :fallback_policy_document, %{}),
      metadata: value(attrs, :metadata, %{})
    }
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp normalize_atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp normalize_atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize_atom(value, _allowed, field) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
