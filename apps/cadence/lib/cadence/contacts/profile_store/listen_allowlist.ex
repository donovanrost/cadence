defmodule Cadence.Contacts.ProfileStore.ListenAllowlist do
  @moduledoc """
  Admission rules for active TCP provider profiles. Plaintext listeners require a source
  allowlist. Mutual TLS listeners require a credential scoped to their provider and transport,
  configured server material, and a valid allowlist when one is supplied.
  """

  alias Cadence.Comms.{PeerAddresses, ProviderDeliveryListenerRead}
  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Secrets.ProviderDeliveryListenerIdentity, as: ServerIdentity

  @doc """
  Whether an active listen-mode TCP provider profile names a usable source allowlist
  (`expected_peer_addresses`, the `Comms.PeerAddresses` rules): `:ok`, or `{:error, reason}`
  with `:peer_addresses_missing` (none), `:peer_addresses_too_broad` (an entry allows every
  address) or `:peer_addresses_invalid` (an entry isn't an address or range). Every provider
  profile write (`persist_provider_profile/1,2`, and `version_provider_profile/4` through it)
  checks it, so no path stores a listening profile the runtime would refuse.
  """
  @spec check(ProviderProfile.t(), binary() | nil) :: :ok | {:error, atom()}
  def check(profile, organization_id \\ nil)

  def check(%ProviderProfile{lifecycle_state: :active, adapter_key: adapter} = profile, org)
      when adapter in [:tcp_socket, "tcp_socket"] do
    config = profile.configuration || %{}

    mode = Map.get(config, "mode", Map.get(config, :mode))
    auth = Map.get(config, "delivery_auth", Map.get(config, :delivery_auth))

    cond do
      mode in ["listen", :listen] ->
        check_listener(profile, org || profile.organization_id, config, auth)

      auth in [nil, "plaintext", :plaintext] ->
        :ok

      true ->
        {:error, :provider_delivery_auth_unsupported}
    end
  end

  def check(%ProviderProfile{}, _org), do: :ok

  defp check_listener(_profile, _org, config, auth) when auth in [nil, "plaintext", :plaintext] do
    config
    |> Map.get("expected_peer_addresses", Map.get(config, :expected_peer_addresses))
    |> PeerAddresses.classify()
    |> allowlist_result()
  end

  defp check_listener(profile, org, config, auth) when auth in ["mtls", :mtls] do
    metadata = profile.metadata || %{}
    peers = Map.get(config, "expected_peer_addresses", Map.get(config, :expected_peer_addresses))

    with :ok <- check_optional_allowlist(peers),
         true <- metadata["transport_origin"] == "provider_managed",
         true <- ServerIdentity.configured?() do
      ProviderDeliveryListenerRead.check_binding(
        org,
        profile.mission_id,
        metadata["mission_provider_id"],
        metadata["materialized_from_transport_id"],
        Map.get(config, "delivery_credential_ref", Map.get(config, :delivery_credential_ref))
      )
    else
      false -> {:error, :delivery_tls_identity_unavailable}
      {:error, _reason} = error -> error
    end
  end

  defp check_listener(_profile, _org, _config, _auth),
    do: {:error, :provider_delivery_auth_unsupported}

  defp check_optional_allowlist(peers) when peers in [nil, []], do: :ok

  defp check_optional_allowlist(peers),
    do: peers |> PeerAddresses.classify() |> allowlist_result()

  defp allowlist_result(:ok), do: :ok
  defp allowlist_result(:empty), do: {:error, :peer_addresses_missing}
  defp allowlist_result(:too_broad), do: {:error, :peer_addresses_too_broad}
  defp allowlist_result(:invalid), do: {:error, :peer_addresses_invalid}
end
