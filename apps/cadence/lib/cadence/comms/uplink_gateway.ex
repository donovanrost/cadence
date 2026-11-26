defmodule Cadence.Comms.UplinkGateway do
  @moduledoc """
  The uplink gateway transport profile behind an outbound route (#44).

  Commanding releases on a contact's selected uplink path through its `uplink_gateway`
  transport binding: COP-1 FOP, TC framing for the route's spacecraft (its scid), sent through
  the transport's TCP listener (`provider_binding_id` = the materialized provider profile). One
  profile per route and content: its id carries a hash of the configuration, so a changed scid
  or frame size gives a new immutable profile.

  The TC frame size comes from the transport's provider delivery profile (`frame_bytes`), so
  Cadence and the provider frame alike; 32 bytes when the provider doesn't say.
  """

  alias Cadence.Comms.{RoutingRule, Transport}
  alias Cadence.Contacts.{ProfileStore, ProviderProfile, TransportProfile}
  alias Cadence.Platform.ContentHash
  alias Cadence.Spacecraft

  @default_frame_size 32

  @spec ensure(RoutingRule.t(), Spacecraft.t(), Transport.t(), ProviderProfile.t()) ::
          {:ok, map()} | {:error, term()}
  def ensure(
        %RoutingRule{} = rule,
        %Spacecraft{} = spacecraft,
        %Transport{} = transport,
        provider
      ) do
    profile = profile(rule, spacecraft, transport, provider)

    with {:ok, profile} <- ProfileStore.persist_transport_profile(rule.organization_id, profile) do
      {:ok, ref(profile)}
    end
  end

  @doc false
  def profile(
        %RoutingRule{} = rule,
        %Spacecraft{} = spacecraft,
        %Transport{} = transport,
        provider
      ) do
    configuration = configuration(spacecraft, transport, provider)
    digest = configuration |> ContentHash.term_sha256() |> binary_part(0, 12)

    TransportProfile.new(%{
      organization_id: rule.organization_id,
      transport_profile_id: "uplink-gateway:#{rule.routing_rule_id}:#{digest}",
      mission_id: rule.mission_id,
      version: 1,
      family_key: :uplink_gateway,
      target_scope: :path,
      configuration: configuration,
      metadata: %{
        "display_name" => "#{rule.display_name} uplink gateway",
        "materialized_from_routing_rule_id" => rule.routing_rule_id
      }
    })
  end

  @doc false
  def ref(%TransportProfile{} = profile),
    do: %{"transport_profile_id" => profile.transport_profile_id, "version" => profile.version}

  defp configuration(spacecraft, transport, provider) do
    %{
      "service_name" => "cop1",
      "transport_profile" => "tc",
      "frame_size" => frame_size(transport),
      "scid" => spacecraft.scid || 0,
      "vcid" => 0,
      "cop1_mode" => "fop",
      # A provider-managed pass can't know the spacecraft FARM's V(R): learn it (#59).
      "cop1_initialization" => "first_clcw",
      "provider_binding_id" => provider.provider_profile_id,
      "provider_adapter_key" => "tcp_socket"
    }
  end

  defp frame_size(%Transport{provider_configuration_snapshot: snapshot}) do
    case get_in(snapshot || %{}, ["delivery_profile", "diagnostics", "frame_bytes"]) do
      size when is_integer(size) and size > 0 -> size
      _other -> @default_frame_size
    end
  end
end
