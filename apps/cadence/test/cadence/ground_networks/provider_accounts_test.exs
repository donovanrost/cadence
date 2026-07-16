defmodule Cadence.GroundNetworks.ProviderAccountsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.GroundNetworks.{
    ProviderAccounts,
    ProviderAudit,
    ProviderCredentials
  }

  @organization_id "org-provider-accounts"
  @mission_id "mission-provider-accounts"
  @account_id "provider-account-alpha"
  @credential_ref "provider-credential-alpha"
  @now ~U[2026-07-15 16:00:00.000000Z]

  setup do
    %{organization: organization} = persist_mission_scope(@organization_id, @mission_id)

    %{organization: organization, admin_scope: scope(organization, :organization_admin)}
  end

  test "creates and versions an account under organization authorization", %{
    organization: organization,
    admin_scope: admin_scope
  } do
    persist_credential!()
    backend = fn _credential, _opts -> {:ok, %{value: "ephemeral-provider-secret"}} end

    assert {:ok, account, version_one} =
             ProviderAccounts.create(admin_scope, account_attrs(),
               secret_backend: backend,
               now: @now
             )

    assert account.organization_id == @organization_id
    assert account.active_version == 1
    assert version_one.provider_account_id == @account_id
    assert version_one.credential_ref == @credential_ref
    refute inspect(account) =~ "ephemeral-provider-secret"
    refute inspect(version_one) =~ "ephemeral-provider-secret"

    assert {:error, :forbidden} =
             ProviderAccounts.version(
               scope(organization, :member),
               @account_id,
               %{region_ref: "us-west-2"},
               validate_credential?: false
             )

    assert {:ok, updated_account, version_two} =
             ProviderAccounts.version(
               admin_scope,
               @account_id,
               %{"region_ref" => "us-west-2", "request_policy" => %{"timeout_ms" => 7_000}},
               validate_credential?: false,
               now: DateTime.add(@now, 60, :second)
             )

    assert updated_account.active_version == 2
    assert version_two.version == 2
    assert version_two.region_ref == "us-west-2"
    assert version_two.request_policy == %{"timeout_ms" => 7_000}

    assert {:ok, historical} =
             ProviderAccounts.fetch_version(@organization_id, @account_id, 1)

    assert historical.region_ref == "local"

    assert {:ok, operational} =
             ProviderAccounts.update_operational_state(@organization_id, @account_id, %{
               event_ingestion_status: :healthy,
               last_validated_at: @now
             })

    assert operational.active_version == 2

    assert {:ok, _rotated} =
             ProviderCredentials.rotate(
               @organization_id,
               @account_id,
               @credential_ref,
               manage_backend?: false,
               now: @now
             )

    assert {:ok, _account, still_version_two} = ProviderAccounts.fetch(admin_scope, @account_id)
    assert still_version_two.version == 2
    assert still_version_two.credential_ref == @credential_ref

    actions =
      @organization_id
      |> ProviderAudit.list_entries(provider_account_id: @account_id, limit: 20)
      |> Enum.map(& &1.action)

    assert "provider_account.created" in actions
    assert "provider_account.versioned" in actions
  end

  test "fails activation when the stable credential cannot be resolved", %{
    admin_scope: admin_scope
  } do
    persist_credential!()

    assert {:error,
            {:provider_account_credential_unavailable, :external_secret_manager_not_configured}} =
             ProviderAccounts.create(admin_scope, account_attrs(), now: @now)

    assert ProviderAccounts.list_for_system(@organization_id) == []
  end

  test "account reads are organization isolated", %{admin_scope: admin_scope} do
    persist_credential!()

    assert {:ok, _account, _version} =
             ProviderAccounts.create(admin_scope, account_attrs(),
               validate_credential?: false,
               now: @now
             )

    assert {:error, :provider_account_not_found} =
             ProviderAccounts.fetch_for_system("another-org", @account_id)
  end

  defp persist_credential! do
    {:ok, credential} =
      ProviderCredentials.create(
        @organization_id,
        @account_id,
        %{
          provider_credential_ref: @credential_ref,
          backend_type: :external,
          backend_key: "providers/alpha/control-plane",
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
      display_name: "Ground Network Simulator",
      provider_type: :simulator,
      client_key: :simulator_http,
      base_url: "http://127.0.0.1:4101",
      region_ref: "local",
      environment_ref: "demo",
      credential_ref: @credential_ref,
      event_ingestion_mode: :polling,
      guardrails: %{
        "allowed_services" => ["telemetry", "tracking"],
        "allowed_directions" => ["downlink", "uplink"],
        "allowed_stations" => ["station-alpha", "station-beta"],
        "max_quota" => 100
      }
    }
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "user-#{role}",
        email: "#{role}@example.test",
        display_name: "#{role}"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
