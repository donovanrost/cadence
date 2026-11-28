defmodule Cadence.Management.Transports do
  @moduledoc """
  Management-plane orchestration for Transport configuration.

  Provider-managed Transports cross the Ground Networks and Comms contexts, so
  this service resolves provider state and passes an immutable, narrowly scoped
  basis into the Comms persistence boundary.

  `derive/3` is the single source of a provider-managed transport's derived configuration: the
  transport change-set kind validates with it, and the console's provider-options read previews
  with it, so a preview shows what an apply stores (comms parity 2).
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.{ProviderTransportBasis, Transport, TransportKind, TransportStore}
  alias Cadence.GroundNetworks.{MissionProviders, ProviderAudit, ProviderAuditEntry}
  alias Cadence.Management.Providers

  @type field_error :: %{path: String.t(), message: String.t()}
  @type derived :: %{
          configuration: map(),
          direction_capability: atom(),
          provider_version: pos_integer(),
          summary: map()
        }

  @spec persist_transport(binary(), Transport.t()) ::
          {:ok, Transport.t()} | {:error, term()}
  def persist_transport(organization_id, %Transport{origin: :direct} = transport)
      when is_binary(organization_id) do
    TransportStore.persist_transport(organization_id, transport)
  end

  def persist_transport(
        organization_id,
        %Transport{origin: :provider_managed, mission_provider_id: provider_id} = transport
      )
      when is_binary(organization_id) and is_binary(provider_id) and provider_id != "" do
    with {:ok, basis} <- basis(organization_id, transport.mission_id, provider_id) do
      TransportStore.persist_transport(organization_id, transport,
        provider_transport_basis: basis
      )
    end
  end

  def persist_transport(organization_id, %Transport{} = transport)
      when is_binary(organization_id) do
    TransportStore.persist_transport(organization_id, transport)
  end

  @doc "The next version of a transport, with the provider basis when it's provider-managed."
  @spec version_transport(binary(), binary(), binary(), map()) ::
          {:ok, Transport.t()} | {:error, term()}
  def version_transport(organization_id, mission_id, transport_id, %{} = attrs),
    do: version_transport(organization_id, mission_id, transport_id, attrs, [])

  defp version_transport(organization_id, mission_id, transport_id, attrs, opts) do
    case attrs do
      %{origin: :provider_managed, mission_provider_id: provider_id}
      when is_binary(provider_id) and provider_id != "" ->
        with {:ok, basis} <- basis(organization_id, mission_id, provider_id) do
          TransportStore.version_transport(
            organization_id,
            mission_id,
            transport_id,
            attrs,
            Keyword.put(opts, :provider_transport_basis, basis)
          )
        end

      _direct ->
        TransportStore.version_transport(organization_id, mission_id, transport_id, attrs, opts)
    end
  end

  @doc "Explicit, audited change from mTLS to a pinned plaintext delivery profile."
  def downgrade_delivery_auth(%Scope{} = scope, mission_id, provider_id, binding_id, params) do
    org = scope.organization_id

    with :ok <-
           Policy.authorize(scope, :"provider_delivery_credential.downgrade", %{
             organization_id: org,
             mission_id: mission_id
           }),
         {:ok, expected, reason, profile_ref} <- downgrade_params(params),
         {:ok, current} <- TransportStore.fetch_transport(org, mission_id, binding_id),
         :ok <- check_downgrade_scope(current, provider_id, expected),
         {:ok, provider} <- MissionProviders.fetch_provider(org, mission_id, provider_id) do
      version_transport(
        org,
        mission_id,
        binding_id,
        %{
          origin: :provider_managed,
          mission_provider_id: provider_id,
          mission_provider_version: provider.version,
          delivery_profile_ref: profile_ref
        },
        authorize_delivery_downgrade: fn current, next ->
          with :ok <- check_downgrade_scope(current, provider_id, expected),
               :ok <- check_downgrade_scope(next, provider_id, expected + 1, "plaintext"),
               {:ok, _entry} <- audit_downgrade(scope, current, next, reason) do
            :ok
          end
        end
      )
    end
  end

  defp downgrade_params(%{
         "expected_version" => version,
         "reason" => reason,
         "delivery_profile_ref" => %{"id" => id, "version" => profile_version}
       })
       when is_integer(version) and version > 0 and is_binary(id) and id != "" and
              is_integer(profile_version) and profile_version > 0 and
              reason in ["provider_compatibility", "operator_requested"] do
    {:ok, version, reason, %{"id" => id, "version" => profile_version}}
  end

  defp downgrade_params(_params), do: {:error, :invalid_delivery_downgrade}

  defp check_downgrade_scope(transport, provider_id, version, mode \\ "mtls") do
    cond do
      transport.mission_provider_id != provider_id ->
        {:error, :transport_not_found}

      transport.version != version ->
        {:error, :version_conflict}

      Map.get(transport.configuration, "delivery_auth", "plaintext") != mode ->
        {:error, :invalid_delivery_downgrade}

      true ->
        :ok
    end
  end

  defp audit_downgrade(scope, current, next, reason) do
    ProviderAudit.append(
      ProviderAuditEntry.new(%{
        organization_id: current.organization_id,
        mission_id: current.mission_id,
        provider_id: current.mission_provider_id,
        action: "provider_delivery_credential.downgrade",
        outcome: "succeeded",
        actor_document: Scope.audit_actor(scope),
        decision_document: %{provider_binding_id: current.transport_id, reason: reason},
        previous_document: %{
          version: current.version,
          delivery_auth: "mtls",
          delivery_profile_ref: current.delivery_profile_ref
        },
        current_document: %{
          version: next.version,
          delivery_auth: "plaintext",
          delivery_profile_ref: next.delivery_profile_ref
        }
      })
    )
  end

  @doc """
  What a provider-managed transport with these refs would store: `document` carries
  `mission_provider_id`, `mission_provider_version`, `service_profile_ref` and
  `delivery_profile_ref` (exact `{"id", "version"}` refs). Field errors name the field to fix.
  """
  @spec derive(binary(), binary(), map()) :: {:ok, derived()} | {:error, [field_error()]}
  def derive(organization_id, mission_id, %{} = document) do
    provider_id = document["mission_provider_id"]

    with {:provider, true} <- {:provider, is_binary(provider_id) and provider_id != ""},
         {:ok, basis} <- basis(organization_id, mission_id, provider_id),
         {:ok, transport} <-
           TransportStore.derive_provider_transport(
             candidate(organization_id, mission_id, document),
             basis
           ) do
      {:ok, derived(transport)}
    else
      {:provider, false} -> {:error, [error("mission_provider_id", "Choose a provider.")]}
      {:error, reason} -> {:error, [field_error(reason)]}
    end
  end

  defp candidate(organization_id, mission_id, document),
    do:
      Transport.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: document["display_name"] || "",
        origin: :provider_managed,
        mission_provider_id: document["mission_provider_id"],
        mission_provider_version: document["mission_provider_version"],
        service_profile_ref: document["service_profile_ref"],
        delivery_profile_ref: document["delivery_profile_ref"]
      })

  defp derived(%Transport{} = transport) do
    {:ok, entry} = TransportKind.fetch(transport.transport_kind)

    %{
      configuration: transport.configuration,
      direction_capability: transport.direction_capability,
      provider_version: transport.mission_provider_version,
      summary: entry.module.display_summary(transport.configuration)
    }
  end

  defp basis(organization_id, mission_id, provider_id) do
    with {:ok, configuration} <-
           Providers.operational_configuration(organization_id, mission_id, provider_id) do
      {:ok, provider_transport_basis(configuration)}
    end
  end

  # Wording for ux to tune; each lands on the field that fixes it.
  defp field_error(:not_found), do: error("mission_provider_id", "That provider doesn't exist.")

  defp field_error(:mission_provider_configuration_scope_mismatch),
    do: error("mission_provider_id", "That provider isn't one of this mission's.")

  defp field_error(:mission_provider_version_not_current),
    do:
      error(
        "mission_provider_version",
        "The provider changed since you chose it. Choose it again."
      )

  defp field_error(:provider_delivery_mtls_unavailable),
    do:
      coded(
        "delivery_profile_ref",
        :provider_delivery_mtls_unavailable,
        "This delivery requires the inbound mutual TLS listener."
      )

  defp field_error(:provider_delivery_auth_unsupported),
    do:
      coded(
        "delivery_profile_ref",
        :provider_delivery_auth_unsupported,
        "The provider has not declared a supported delivery identity for this profile."
      )

  defp field_error(:mission_provider_not_active),
    do: error("mission_provider_id", "That provider isn't active.")

  defp field_error(:mission_provider_not_validated),
    do: error("mission_provider_id", "That provider isn't validated and healthy yet.")

  defp field_error(:mission_provider_profiles_not_synced),
    do: error("mission_provider_id", "That provider's profiles haven't synced yet.")

  defp field_error({:provider_profile_not_found, "service_profiles"}),
    do: error("service_profile_ref", "Choose one of the provider's service profiles.")

  defp field_error({:provider_profile_not_found, "delivery_profiles"}),
    do: error("delivery_profile_ref", "Choose one of the provider's delivery profiles.")

  defp field_error(:provider_service_profile_not_active),
    do: error("service_profile_ref", "That service profile isn't active.")

  defp field_error(:provider_delivery_profile_not_ready),
    do: error("delivery_profile_ref", "That delivery profile isn't ready.")

  defp field_error(reason)
       when reason in [
              :provider_profile_direction_not_supported,
              :provider_profiles_not_compatible
            ],
       do: error("delivery_profile_ref", "That delivery profile doesn't carry this service.")

  # #990 (DECISIONS #115): a listening transport takes its allowlist from the provider's egress.
  defp field_error(:provider_egress_addresses_missing),
    do:
      coded(
        "delivery_profile_ref",
        :provider_egress_addresses_missing,
        "That delivery profile doesn't say which addresses the provider connects from, so " <>
          "Cadence can't listen for it."
      )

  defp field_error(:provider_egress_addresses_too_broad),
    do:
      coded(
        "delivery_profile_ref",
        :provider_egress_addresses_too_broad,
        "That delivery profile's source addresses allow every address, so Cadence can't " <>
          "listen for it."
      )

  defp field_error(:provider_egress_addresses_invalid),
    do:
      coded(
        "delivery_profile_ref",
        :provider_egress_addresses_invalid,
        "That delivery profile's source addresses aren't IP addresses or CIDR ranges, so " <>
          "Cadence can't listen for it."
      )

  defp field_error({:provider_delivery_profile_unusable, message}) when is_binary(message),
    do:
      error("delivery_profile_ref", "This transport can't use that delivery profile: #{message}")

  defp field_error(_reason),
    do: error("mission_provider_id", "The provider's details couldn't be read. Try again.")

  defp error(path, message), do: %{path: path, message: message}
  defp coded(path, code, message), do: %{path: path, message: message, code: Atom.to_string(code)}

  defp provider_transport_basis(configuration) do
    provider = configuration.provider

    %ProviderTransportBasis{
      organization_id: configuration.organization_id,
      mission_id: configuration.mission_id,
      provider_id: configuration.provider_id,
      provider_version: configuration.provider_version,
      display_name: provider.display_name,
      provider_type: provider.provider_type,
      environment_ref: provider.environment_ref,
      lifecycle_state: provider.lifecycle_state,
      last_validated_at: provider.last_validated_at,
      last_synced_at: provider.last_synced_at,
      control_status: get_in(provider.metadata, ["control_plane", "status"]),
      inventory_sync_document: provider.inventory_sync_document,
      delivery_auth:
        if(get_in(provider.capabilities_document, ["delivery", "delivery_auth"]) == "mtls",
          do: :mtls
        )
    }
  end
end
