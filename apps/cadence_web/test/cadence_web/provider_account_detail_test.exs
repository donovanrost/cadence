defmodule CadenceWeb.ProviderAccountDetailTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext, OrganizationAdminAction}
  alias Cadence.Applications.OrganizationAdminProviders.ProviderAccountShow
  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts, ProviderCredentials}
  alias CadenceWeb.TestFixtures

  setup do
    organization = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization_membership: membership
      })

    mission = TestFixtures.persist_mission!(organization)
    original = Application.fetch_env(:cadence, :provider_account_live_opts)

    Application.put_env(:cadence, :provider_account_live_opts,
      manage_backend?: false,
      validate_credential?: false
    )

    on_exit(fn ->
      case original do
        {:ok, opts} -> Application.put_env(:cadence, :provider_account_live_opts, opts)
        :error -> Application.delete_env(:cadence, :provider_account_live_opts)
      end
    end)

    model = account!(scope)
    %{scope: scope, organization: organization, mission: mission, model: model}
  end

  test "detail DTO and completed grant DTO pass the feature reader and renderer", %{
    scope: scope,
    mission: mission,
    model: model
  } do
    assert model.account.organization_id == scope.organization_id
    assert model.account.version == 1
    assert model.account.credential_version == 1

    assert {:ok, %{patch: granted}} =
             execute(scope, "grant_provider_account_mission", model, %{
               "grant" => %{
                 "mission_id" => mission.mission_id,
                 "max_quota" => "0",
                 "grant_reason" => "Commissioning"
               }
             })

    assert [grant] = granted.account_grants
    assert grant.mission_id == mission.mission_id
    assert grant.account_version == model.account.version

    assert {:ok, saved} =
             ProviderAccountGrants.fetch_active_for_system(scope.organization_id, grant.id)

    assert saved.restrictions["max_quota"] == 0

    assert {:ok, %{patch: revoked}} =
             execute(scope, "revoke_provider_account_mission", granted, %{
               "grant-id" => grant.id,
               "expected_grant_version" => grant.version
             })

    assert [revoked_grant] = revoked.account_grants
    assert revoked_grant.version == grant.version + 1
    assert revoked_grant.lifecycle.status == "blocked"
    assert is_nil(revoked_grant.revoke)

    checker =
      Path.expand(
        "../../../../frontend/modules/communications/src/features/provider-accounts/producer-render-check.mjs",
        __DIR__
      )

    samples =
      Enum.map([model, granted, revoked], fn dto ->
        %{
          component: "ProviderAccountShow",
          organization_id: scope.organization_id,
          props: dto,
          ids: [dto.page.id, dto.grant_form.id] ++ Enum.map(dto.account_grants, & &1.__dom_id)
        }
      end)

    node = System.find_executable("node") || flunk("Node required for the feature contract")
    {output, status} = System.cmd(node, [checker, Jason.encode!(samples)], stderr_to_stdout: true)
    assert status == 0, output
  end

  test "missing, malformed and stale snapshots reject all detail effects", %{
    scope: scope,
    model: model
  } do
    for action <- [
          "validate_provider_account",
          "rotate_provider_credential",
          "revoke_provider_credential",
          "grant_provider_account_mission",
          "revoke_provider_account_mission"
        ],
        invalid <- [
          %{"expected_account_version" => nil},
          %{"expected_account_version" => "1"},
          %{"expected_account_version" => 0},
          %{"credential_ref" => "other-ref"},
          %{"expected_credential_version" => 0}
        ] do
      assert {:error, %ActionFailure{code: "stale_provider_account"}} =
               execute(scope, action, model, invalid)
    end

    assert {:ok, current} = ProviderAccountShow.props(scope, model.account.provider_account_id)
    assert current.account == model.account
    assert current.account_audit == model.account_audit
  end

  test "rotation consumes a credential snapshot and old snapshots cannot replay it", %{
    scope: scope,
    model: model
  } do
    assert {:ok, %{patch: rotated}} = execute(scope, "rotate_provider_credential", model)
    assert rotated.account.credential_version == model.account.credential_version + 1

    assert {:error, %ActionFailure{code: "stale_provider_account"}} =
             execute(scope, "rotate_provider_credential", model)

    assert {:ok, %{patch: revoked}} = execute(scope, "revoke_provider_credential", rotated)
    assert revoked.account.credential_status == "revoked"
    assert revoked.actions.validate.disabled
    assert revoked.actions.rotate.disabled
    assert is_nil(revoked.actions.revoke)

    assert {:error, %ActionFailure{code: "stale_provider_account"}} =
             execute(scope, "revoke_provider_credential", rotated)
  end

  test "grants from another account and stale grant versions cannot be revoked", %{
    scope: scope,
    mission: mission,
    model: model
  } do
    other = account!(scope)

    assert {:ok, %{patch: granted}} =
             execute(scope, "grant_provider_account_mission", other, %{
               "grant" => %{"mission_id" => mission.mission_id}
             })

    assert [grant] = granted.account_grants
    params = %{"grant-id" => grant.id, "expected_grant_version" => grant.version}

    assert {:error, %ActionFailure{code: "stale_provider_account"}} =
             execute(scope, "revoke_provider_account_mission", model, params)

    assert {:error, %ActionFailure{code: "stale_provider_account"}} =
             execute(scope, "revoke_provider_account_mission", granted, %{
               params
               | "expected_grant_version" => grant.version + 1
             })

    assert {:ok, unchanged} =
             ProviderAccountGrants.fetch_active_for_system(scope.organization_id, grant.id)

    assert unchanged.version == grant.version
  end

  test "account version changes require a fresh snapshot", %{scope: scope, model: model} do
    assert {:ok, _account, version} =
             ProviderAccounts.version(
               scope,
               model.account.provider_account_id,
               %{region_ref: "updated"},
               validate_credential?: false
             )

    assert version.version == model.account.version + 1

    assert {:error, %ActionFailure{code: "stale_provider_account"}} =
             execute(scope, "rotate_provider_credential", model)

    assert {:ok, current} = ProviderAccountShow.props(scope, model.account.provider_account_id)
    assert current.account.credential_version == model.account.credential_version
  end

  test "ordinary members and foreign organization scopes cannot act", %{
    scope: scope,
    organization: organization,
    model: model
  } do
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, organization, role: :member)

    member =
      Scope.new(%{
        user: user,
        organization_id: scope.organization_id,
        organization_membership: membership
      })

    assert {:error, :forbidden} = execute(member, "rotate_provider_credential", model)
    other_org = TestFixtures.persist_org!()
    other_membership = TestFixtures.grant_membership!(user, other_org, role: :organization_admin)

    foreign =
      Scope.new(%{
        user: user,
        organization_id: other_org.organization_id,
        organization_membership: other_membership
      })

    assert {:error, :provider_account_not_found} =
             execute(foreign, "rotate_provider_credential", model)
  end

  defp execute(scope, action, model, extra \\ %{}) do
    identity = model.account

    params =
      Map.merge(
        %{
          "provider_account_id" => identity.provider_account_id,
          "expected_account_version" => identity.version,
          "credential_ref" => identity.credential_ref,
          "expected_credential_version" => identity.credential_version
        },
        extra
      )

    OrganizationAdminAction.execute(
      scope,
      HostContext.organization(scope.organization_id),
      %ActionRequest{
        application_key: "organization_admin",
        application_version: 1,
        surface_id: "provider_account_show",
        surface_version: 1,
        action_id: action,
        params: params
      }
    )
  end

  defp account!(scope) do
    suffix = System.unique_integer([:positive])
    account_id = "detail-account-#{suffix}"
    credential_ref = "detail-credential-#{suffix}"

    assert {:ok, _credential} =
             ProviderCredentials.create(
               scope.organization_id,
               account_id,
               %{
                 provider_credential_ref: credential_ref,
                 backend_type: :external,
                 backend_key: "fixture/detail/#{suffix}",
                 registered_at: ~U[2026-09-07 10:00:00.000000Z]
               },
               manage_backend?: false
             )

    assert {:ok, _account, _version} =
             ProviderAccounts.create(
               scope,
               %{
                 provider_account_id: account_id,
                 display_name: "Detail Provider",
                 provider_type: :simulator,
                 base_url: "https://provider.example.test",
                 region_ref: "test",
                 environment_ref: "test",
                 credential_ref: credential_ref,
                 guardrails: %{"max_quota" => 10}
               },
               validate_credential?: false
             )

    assert {:ok, model} = ProviderAccountShow.props(scope, account_id)
    model
  end
end
