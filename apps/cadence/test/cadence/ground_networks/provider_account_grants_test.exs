defmodule Cadence.GroundNetworks.ProviderAccountGrantsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.TransportStore

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.ProviderReservations

  alias Cadence.GroundNetworks.{
    MissionProvider,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  @organization_id "org-provider-grants"
  @mission_id "mission-provider-grants"
  @account_id "provider-account-grant-alpha"
  @credential_ref "provider-credential-grant-alpha"
  @grant_id "mission-provider-grant-alpha"
  @now ~U[2026-07-15 17:00:00.000000Z]

  setup do
    %{organization: organization} = persist_mission_scope(@organization_id, @mission_id)
    scope = admin_scope(organization)
    persist_credential!()

    {:ok, account, account_version} =
      ProviderAccounts.create(scope, account_attrs(),
        validate_credential?: false,
        now: @now
      )

    %{
      scope: scope,
      account: account,
      account_version: account_version
    }
  end

  test "grants only narrow account guardrails and retain exact versions", %{
    scope: scope,
    account_version: account_version
  } do
    assert {:error, :provider_account_grant_widens_guardrails} =
             ProviderAccountGrants.grant(
               scope,
               @mission_id,
               @account_id,
               %{
                 restrictions: %{
                   "allowed_stations" => ["station-outside-guardrail"]
                 }
               },
               now: @now
             )

    assert {:ok, grant} = persist_grant!(scope)
    assert grant.provider_account_version == account_version.version
    assert grant.restrictions["allowed_services"] == ["telemetry"]
    assert grant.restrictions["max_quota"] == 50

    assert {:ok, exact} =
             ProviderAccountGrants.fetch_version(
               @organization_id,
               grant.provider_account_grant_id,
               @mission_id,
               1
             )

    assert exact == grant

    assert {:error, :provider_account_grant_not_found} =
             ProviderAccountGrants.fetch_version(
               "another-org",
               grant.provider_account_grant_id,
               @mission_id,
               1
             )
  end

  test "mission Providers bind exact account and grant versions", %{
    scope: scope,
    account_version: account_version
  } do
    {:ok, grant} = persist_grant!(scope)

    provider =
      MissionProvider.new(%{
        mission_id: @mission_id,
        display_name: "Simulator via account grant",
        provider_account_id: @account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        provider_type: account_version.provider_type,
        client_key: account_version.client_key,
        base_url: account_version.base_url,
        credential_ref: account_version.credential_ref,
        environment_ref: account_version.environment_ref,
        delivery_policy_document: %{"maximum_later_start_shift_seconds" => 120},
        permitted_resource_refs: ["station-alpha"]
      })

    assert {:ok, persisted} = MissionProviders.persist_provider(@organization_id, provider)
    assert persisted.provider_account_id == @account_id
    assert persisted.provider_account_grant_id == grant.provider_account_grant_id

    assert {:ok, context} =
             Cadence.GroundNetworks.context_from_provider(persisted)

    assert context.base_url == account_version.base_url
    assert context.credential_ref == @credential_ref

    mismatched = %{provider | base_url: "https://wrong.example.test"}

    assert {:error, :mission_provider_account_configuration_mismatch} =
             MissionProviders.persist_provider(@organization_id, mismatched)
  end

  test "one organization account can be granted independently to two missions", %{
    scope: scope
  } do
    second_mission_id = "mission-provider-grants-secondary"
    persist_mission_scope(@organization_id, second_mission_id)

    assert {:ok, first_grant} = persist_grant!(scope)

    assert {:ok, second_grant} =
             ProviderAccountGrants.grant(
               scope,
               second_mission_id,
               @account_id,
               %{
                 provider_account_grant_id: "mission-provider-grant-secondary",
                 restrictions: %{"allowed_services" => ["tracking"]}
               },
               now: @now
             )

    assert first_grant.provider_account_id == second_grant.provider_account_id
    assert first_grant.mission_id == @mission_id
    assert second_grant.mission_id == second_mission_id

    assert {:error, :provider_account_grant_not_found} =
             ProviderAccountGrants.fetch_version(
               @organization_id,
               first_grant.provider_account_grant_id,
               second_mission_id,
               first_grant.version
             )
  end

  test "revocation blocks new bindings while preserving historical grant reads", %{
    scope: scope,
    account_version: account_version
  } do
    {:ok, grant} = persist_grant!(scope)
    {provider, transport} = persist_bound_provider!(grant, account_version)
    {:ok, reservation} = persist_nonterminal_reservation!(grant, provider, transport)

    assert {:ok, revoked} =
             ProviderAccountGrants.revoke(
               scope,
               grant.provider_account_grant_id,
               "Commercial authorization removed",
               now: DateTime.add(@now, 60, :second)
             )

    assert revoked.lifecycle_state == :revoked
    assert revoked.version == 2

    assert {:error, :provider_account_grant_revoked} =
             ProviderAccountGrants.fetch_active_for_system(
               @organization_id,
               grant.provider_account_grant_id
             )

    assert {:ok, historical} =
             ProviderAccountGrants.fetch_version(
               @organization_id,
               grant.provider_account_grant_id,
               @mission_id,
               1
             )

    assert historical.lifecycle_state == :active

    assert {:ok, marked} =
             ProviderReservations.fetch(
               @organization_id,
               @mission_id,
               reservation.provider_reservation_id
             )

    assert marked.lifecycle_state == :pending

    assert marked.operator_review_document["provider_grant_review"]["grant_id"] ==
             grant.provider_account_grant_id

    assert marked.operator_review_document["provider_grant_review"]["reason"] ==
             "Commercial authorization removed"

    assert {:error, :provider_account_grant_revoked} =
             ProviderAccountGrants.validate_binding(
               @organization_id,
               @mission_id,
               @account_id,
               1,
               grant.provider_account_grant_id,
               1
             )
  end

  defp persist_grant!(scope) do
    ProviderAccountGrants.grant(
      scope,
      @mission_id,
      @account_id,
      %{
        provider_account_grant_id: @grant_id,
        restrictions: %{
          "allowed_services" => ["telemetry"],
          "allowed_directions" => ["downlink"],
          "allowed_stations" => ["station-alpha"],
          "max_quota" => 50
        },
        grant_reason: "Flight operations"
      },
      now: @now
    )
  end

  defp persist_bound_provider!(grant, account_version) do
    provider =
      MissionProvider.new(%{
        provider_id: "mission-provider-bound-to-grant",
        mission_id: @mission_id,
        display_name: "Simulator via account grant",
        provider_account_id: @account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        provider_type: account_version.provider_type,
        client_key: account_version.client_key,
        base_url: account_version.base_url,
        credential_ref: account_version.credential_ref,
        environment_ref: account_version.environment_ref
      })

    {:ok, provider} = MissionProviders.persist_provider(@organization_id, provider)

    {:ok, transport} =
      TransportStore.persist_transport(
        @organization_id,
        Transport.new(%{
          transport_id: "transport-pending-grant-review",
          mission_id: @mission_id,
          display_name: "Pending grant review",
          origin: :direct,
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "0.0.0.0",
            "port" => 5_200,
            "framing_mode" => "fixed_size",
            "frame_size" => 1_115,
            "tls_enabled" => false
          }
        })
      )

    {provider, transport}
  end

  defp persist_nonterminal_reservation!(grant, provider, transport) do
    ProviderReservations.create_attempt(@organization_id, %{
      provider_reservation_id: "reservation-pending-grant-review",
      mission_id: @mission_id,
      provider_id: provider.provider_id,
      provider_version: provider.version,
      provider_account_id: grant.provider_account_id,
      provider_account_version: grant.provider_account_version,
      provider_account_grant_id: grant.provider_account_grant_id,
      provider_account_grant_version: grant.version,
      transport_id: transport.transport_id,
      transport_version: transport.version,
      service_profile_ref: %{"id" => "telemetry", "version" => 1},
      delivery_profile_ref: %{"id" => "cadence", "version" => 1},
      provider_profile_id: "provider-profile-pending-grant-review",
      provider_profile_version: 1,
      scheduled_contact_id: "scheduled-contact-pending-grant-review",
      provider_opportunity_ref: "opportunity-pending-grant-review",
      idempotency_key: "idempotency-pending-grant-review",
      lifecycle_state: :pending,
      spacecraft_id: "spacecraft-pending-grant-review",
      provider_spacecraft_ref: "SC-PENDING-REVIEW",
      starts_at: DateTime.add(@now, 300, :second),
      ends_at: DateTime.add(@now, 900, :second)
    })
  end

  defp persist_credential! do
    {:ok, credential} =
      ProviderCredentials.create(
        @organization_id,
        @account_id,
        %{
          provider_credential_ref: @credential_ref,
          backend_type: :external,
          backend_key: "providers/grants/control-plane",
          registered_at: @now
        },
        manage_backend?: false,
        now: @now
      )

    credential
  end

  defp account_attrs do
    %{
      provider_account_id: @account_id,
      display_name: "Grant Simulator",
      provider_type: :simulator,
      base_url: "http://127.0.0.1:4101",
      region_ref: "local",
      environment_ref: "demo",
      credential_ref: @credential_ref,
      guardrails: %{
        "allowed_services" => ["telemetry", "tracking"],
        "allowed_directions" => ["downlink", "uplink"],
        "allowed_stations" => ["station-alpha", "station-beta"],
        "max_quota" => 100
      }
    }
  end

  defp admin_scope(organization) do
    user =
      User.new(%{
        user_id: "user-provider-grant-admin",
        email: "grant-admin@example.test",
        display_name: "Grant Admin"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: :organization_admin
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
