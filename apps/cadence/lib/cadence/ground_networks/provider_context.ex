defmodule Cadence.GroundNetworks.ProviderContext do
  @moduledoc "Provider-neutral control-plane context for one mission provider binding."

  alias Cadence.Contacts.ProviderProfile
  alias Cadence.GroundNetworks.ProviderCapabilities

  @type t :: %__MODULE__{
          provider_ref: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          client_key: binary() | nil,
          base_url: binary() | nil,
          credential_ref: binary() | nil,
          environment_ref: binary() | nil,
          capabilities: ProviderCapabilities.t() | nil,
          metadata: map()
        }

  defstruct [
    :provider_ref,
    :organization_id,
    :mission_id,
    :client_key,
    :base_url,
    :credential_ref,
    :environment_ref,
    :capabilities,
    metadata: %{}
  ]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, provider_ref} <- required(attrs, :provider_ref),
         {:ok, mission_id} <- required(attrs, :mission_id),
         {:ok, capabilities} <- normalize_capabilities(value(attrs, :capabilities)) do
      {:ok,
       %__MODULE__{
         provider_ref: provider_ref,
         organization_id: value(attrs, :organization_id),
         mission_id: mission_id,
         client_key: optional_binary(value(attrs, :client_key)),
         base_url: optional_binary(value(attrs, :base_url)),
         credential_ref: optional_binary(value(attrs, :credential_ref)),
         environment_ref: optional_binary(value(attrs, :environment_ref)),
         capabilities: capabilities,
         metadata: value(attrs, :metadata, %{})
       }}
    end
  end

  @doc "Temporary bridge until Stage 2 mission Provider persistence replaces ProviderProfile setup."
  @spec from_provider_profile(ProviderProfile.t()) :: {:ok, t()} | {:error, term()}
  def from_provider_profile(%ProviderProfile{} = profile) do
    scheduling = scheduling_config(profile)

    new(%{
      provider_ref: profile.provider_profile_id,
      organization_id: profile.organization_id,
      mission_id: profile.mission_id,
      client_key: scheduling["client"],
      base_url: scheduling["base_url"],
      credential_ref: credential_ref(profile, scheduling),
      environment_ref: scheduling["environment_ref"] || scheduling["run_id"],
      capabilities: scheduling["capabilities"],
      metadata: profile.metadata
    })
  end

  @doc "Adds a request-local resolver for pre-MissionProvider profiles that still contain a token."
  @spec with_legacy_credential(ProviderProfile.t(), t(), keyword()) :: keyword()
  def with_legacy_credential(%ProviderProfile{} = profile, %__MODULE__{} = context, opts) do
    token = scheduling_config(profile)["api_token"]

    if is_binary(token) and token != "" and is_binary(context.credential_ref) do
      resolver = fn reference ->
        resolve_legacy_credential(reference, context.credential_ref, token)
      end

      Keyword.put_new(opts, :credential_resolver, resolver)
    else
      opts
    end
  end

  defp resolve_legacy_credential(reference, reference, token), do: {:ok, token}

  defp resolve_legacy_credential(_reference, _expected_reference, _token),
    do: {:error, :credential_reference_not_found}

  defp scheduling_config(%ProviderProfile{configuration: configuration}) do
    Map.get(configuration, "scheduling", Map.get(configuration, :scheduling, %{}))
  end

  defp credential_ref(profile, scheduling) do
    scheduling["credential_ref"] ||
      if is_binary(scheduling["api_token"]) and scheduling["api_token"] != "" do
        "legacy-provider-profile:#{profile.provider_profile_id}:#{profile.version}"
      end
  end

  defp normalize_capabilities(nil), do: {:ok, nil}
  defp normalize_capabilities(%ProviderCapabilities{} = capabilities), do: {:ok, capabilities}
  defp normalize_capabilities(capabilities), do: ProviderCapabilities.from_external(capabilities)

  defp required(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid_provider_context, key}}
    end
  end

  defp optional_binary(value) when is_binary(value) and value != "", do: value
  defp optional_binary(_value), do: nil

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
