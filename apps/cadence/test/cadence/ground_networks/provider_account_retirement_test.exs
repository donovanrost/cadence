defmodule Cadence.GroundNetworks.ProviderAccountRetirementTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.GroundNetworks.{
    MissionProvider,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAccountRename,
    ProviderAccountRetirement,
    ProviderAccounts,
    ProviderCredentials
  }

  @org "org-provider-retire"
  @mission "mission-provider-retire"
  @account "provider-account-retire"
  @credential "provider-credential-retire"
  @now ~U[2026-07-15 17:00:00.000000Z]

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)
    scope = scope(organization, :organization_admin)

    {:ok, _} =
      ProviderCredentials.create(
        @org,
        @account,
        %{
          provider_credential_ref: @credential,
          backend_type: :external,
          backend_key: "providers/retire",
          registered_at: @now
        },
        manage_backend?: false,
        now: @now
      )

    {:ok, _account, version} =
      ProviderAccounts.create(
        scope,
        %{
          provider_account_id: @account,
          display_name: "Retiring Simulator",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          region_ref: "local",
          environment_ref: "demo",
          credential_ref: @credential,
          guardrails: %{"allowed_services" => ["telemetry"], "allowed_directions" => ["downlink"]}
        },
        validate_credential?: false,
        now: @now
      )

    %{scope: scope, organization: organization, version: version}
  end

  test "an account a mission uses can't be retired; an unused one can", ctx do
    {:ok, grant} =
      ProviderAccountGrants.grant(ctx.scope, @mission, @account, %{grant_reason: "Ops"},
        now: @now
      )

    {:ok, provider} =
      MissionProviders.persist_provider(
        @org,
        MissionProvider.new(%{
          provider_id: "mission-provider-retire",
          mission_id: @mission,
          display_name: "Simulator",
          provider_account_id: @account,
          provider_account_version: ctx.version.version,
          provider_account_grant_id: grant.provider_account_grant_id,
          provider_account_grant_version: grant.version,
          provider_type: ctx.version.provider_type,
          client_key: ctx.version.client_key,
          base_url: ctx.version.base_url,
          credential_ref: ctx.version.credential_ref,
          environment_ref: ctx.version.environment_ref
        })
      )

    assert {:error, {:in_use, [%{mission_id: @mission, provider_id: "mission-provider-retire"}]}} =
             ProviderAccountRetirement.retire(ctx.scope, @account, "Contract ended")

    {:ok, _} = MissionProviders.archive_provider(@org, @mission, provider.provider_id)

    assert {:ok,
            %{
              lifecycle_state: :archived,
              metadata: %{"retired" => %{"reason" => "Contract ended"}}
            }} =
             ProviderAccountRetirement.retire(ctx.scope, @account, "Contract ended")

    assert {:error, :already_retired} = ProviderAccountRetirement.retire(ctx.scope, @account)

    # L13 defect 3: a grant on a retired account says so, not "widens guardrails".
    assert {:error, :provider_account_archived} =
             ProviderAccountGrants.grant(ctx.scope, @mission, @account, %{}, now: @now)
  end

  test "only organization admins retire accounts, and unknown accounts are not found", ctx do
    assert {:error, :forbidden} =
             ProviderAccountRetirement.retire(scope(ctx.organization, :member), @account)

    assert {:error, :provider_account_not_found} =
             ProviderAccountRetirement.retire(ctx.scope, "no-such-account")
  end

  test "an admin renames an account without a new version; bad names and others are refused",
       ctx do
    assert {:ok, %{display_name: "Earendil KSAT", active_version: version}} =
             ProviderAccountRename.rename(ctx.scope, @account, "  Earendil KSAT  ")

    assert version == ctx.version.version

    assert {:error, :invalid_display_name} =
             ProviderAccountRename.rename(ctx.scope, @account, " ")

    assert {:error, :provider_account_not_found} =
             ProviderAccountRename.rename(ctx.scope, "no-such-account", "X")

    assert {:error, :forbidden} =
             ProviderAccountRename.rename(scope(ctx.organization, :member), @account, "X")
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "user-retire-#{role}",
        email: "#{role}@example.test",
        display_name: "R"
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user.user_id,
          organization_id: organization.organization_id,
          role: role
        })
    })
  end
end
