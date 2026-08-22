defmodule Cadence.Management.Providers.ProviderConfiguration do
  @moduledoc "Immutable Management fact describing one exact provider configuration."

  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Platform.ContentHash

  @type t :: %__MODULE__{
          organization_id: binary(),
          mission_id: binary(),
          provider_id: binary(),
          provider_version: pos_integer(),
          content_sha256: binary(),
          provider: MissionProvider.t()
        }

  @enforce_keys [
    :organization_id,
    :mission_id,
    :provider_id,
    :provider_version,
    :content_sha256,
    :provider
  ]
  defstruct @enforce_keys

  @spec new(MissionProvider.t()) :: t()
  def new(%MissionProvider{} = provider) do
    %__MODULE__{
      organization_id: provider.organization_id,
      mission_id: provider.mission_id,
      provider_id: provider.provider_id,
      provider_version: provider.version,
      content_sha256: ContentHash.term_sha256(configuration_basis(provider)),
      provider: provider
    }
  end

  @spec matches?(t(), MissionProvider.t()) :: boolean()
  def matches?(%__MODULE__{} = configuration, %MissionProvider{} = provider) do
    configuration.organization_id == provider.organization_id and
      configuration.mission_id == provider.mission_id and
      configuration.provider_id == provider.provider_id and
      configuration.provider_version == provider.version and
      configuration.content_sha256 == ContentHash.term_sha256(configuration_basis(provider))
  end

  defp configuration_basis(provider) do
    provider
    |> Map.from_struct()
    |> Map.drop([
      :capabilities_document,
      :inventory_sync_document,
      :last_validated_at,
      :last_synced_at
    ])
  end
end
