defmodule Cadence.Contacts.ProfileStore.ListenAllowlist do
  @moduledoc """
  The source-allowlist rule every provider-profile write applies (#990, DECISIONS #115): an active
  listen-mode TCP profile must name the peers it accepts, by the `Comms.PeerAddresses` rules.
  `ProfileStore` checks it before storing, so no write path keeps a listening profile the runtime
  would refuse.
  """

  alias Cadence.Comms.PeerAddresses
  alias Cadence.Contacts.ProviderProfile

  @doc """
  Whether an active listen-mode TCP provider profile names a usable source allowlist
  (`expected_peer_addresses`, the `Comms.PeerAddresses` rules): `:ok`, or `{:error, reason}`
  with `:peer_addresses_missing` (none), `:peer_addresses_too_broad` (an entry allows every
  address) or `:peer_addresses_invalid` (an entry isn't an address or range). Every provider
  profile write (`persist_provider_profile/1,2`, and `version_provider_profile/4` through it)
  checks it, so no path stores a listening profile the runtime would refuse.
  """
  @spec check(ProviderProfile.t()) :: :ok | {:error, atom()}
  def check(%ProviderProfile{lifecycle_state: :active, adapter_key: adapter} = profile)
      when adapter in [:tcp_socket, "tcp_socket"] do
    config = profile.configuration || %{}

    if Map.get(config, "mode", Map.get(config, :mode)) in ["listen", :listen] do
      config
      |> Map.get("expected_peer_addresses", Map.get(config, :expected_peer_addresses))
      |> PeerAddresses.classify()
      |> allowlist_result()
    else
      :ok
    end
  end

  def check(%ProviderProfile{}), do: :ok

  defp allowlist_result(:ok), do: :ok
  defp allowlist_result(:empty), do: {:error, :peer_addresses_missing}
  defp allowlist_result(:too_broad), do: {:error, :peer_addresses_too_broad}
  defp allowlist_result(:invalid), do: {:error, :peer_addresses_invalid}
end
