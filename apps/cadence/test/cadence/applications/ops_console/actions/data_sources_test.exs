defmodule Cadence.Applications.OpsConsole.Actions.DataSourcesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.DataSources, as: DataSourcesAction
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources

  @organization_id "org-ops-data-sources-actions"
  @mission_id "mission-ops-data-sources-actions"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "declares the exact durable host bindings for the data-sources surface" do
    assert DataSourcesAction.bindings() == [
             {"data_sources", "register-source"},
             {"data_sources", "change-binding"},
             {"data_sources", "disable-source"},
             {"data_sources", "enable-source"},
             {"data_sources", "reconcile-tsdb-backend"},
             {"data_sources", "deprovision-tsdb-backend"},
             {"data_sources", "provision-tsdb-backend"},
             {"data_sources", "probe-source"},
             {"data_sources", "rotate-source-credential"},
             {"data_sources", "retry-deployment-run"},
             {"data_sources", "requeue-deployment-run"},
             {"data_source_registration", "register-source"},
             {"data_source_settings", "change-binding"},
             {"data_source_settings", "disable-source"},
             {"data_source_settings", "enable-source"},
             {"data_source_settings", "reconcile-tsdb-backend"},
             {"data_source_settings", "deprovision-tsdb-backend"},
             {"data_source_settings", "provision-tsdb-backend"},
             {"data_source_settings", "probe-source"},
             {"data_source_settings", "rotate-source-credential"},
             {"data_source_settings", "retry-deployment-run"},
             {"data_source_settings", "requeue-deployment-run"}
           ]
  end

  test "register-source executes the scoped domain persistence and returns JSON-safe output" do
    request =
      request("register-source", %{
        "source" => %{
          "data_source_id" => "action-managed-source",
          "logical_source" => "telemetry",
          "kind" => "managed_tsdb",
          "isolation_level" => "mission_isolated",
          "credentials_ref" => "",
          "credential_provider" => "questdb",
          "endpoint_ref" => "",
          "material_env_profile" => "",
          "http_endpoint_env" => "",
          "storage" => "questdb"
        }
      })

    assert {:ok, %DataSource{} = source} =
             DataSourcesAction.execute(
               scope(),
               HostContext.mission(@mission_id),
               "data_sources",
               request
             )

    assert source.data_source_id == "action-managed-source"
    assert source.organization_id == @organization_id
    assert source.mission_id == @mission_id

    assert DataSourcesAction.result(source) == %{
             "dataSourceId" => "action-managed-source",
             "organizationId" => @organization_id,
             "missionId" => @mission_id,
             "status" => "active",
             "kind" => "managed_tsdb",
             "isolationLevel" => "mission_isolated"
           }
  end

  test "rejects a resource from another mission before domain mutation" do
    persist_mission_scope(@organization_id, "mission-other")

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "other-mission-source",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: @organization_id,
               mission_id: "mission-other",
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true},
               metadata: %{storage: :questdb}
             })

    request = request("disable-source", %{"data-source-id" => "other-mission-source"})

    assert {:error, :scope_mismatch} =
             DataSourcesAction.execute(
               scope(),
               HostContext.mission(@mission_id),
               "data_sources",
               request
             )
  end

  test "rejects a cross-mission parameter" do
    request =
      request("disable-source", %{
        "data-source-id" => "source-1",
        "mission_id" => "mission-other"
      })

    assert {:error, :scope_mismatch} =
             DataSourcesAction.execute(
               scope(),
               HostContext.mission(@mission_id),
               "data_sources",
               request
             )
  end

  test "rejects unknown and malformed actions fail-closed" do
    assert {:error, :unsupported_application_action} =
             DataSourcesAction.execute(
               scope(),
               HostContext.mission(@mission_id),
               "data_sources",
               request("unknown-source-action", %{})
             )

    assert {:error, :malformed_action_input} =
             DataSourcesAction.execute(
               scope(),
               HostContext.mission(@mission_id),
               "data_sources",
               request("disable-source", %{"data-source-id" => self()})
             )
  end

  describe "writes only on the caller's own sources (shared and other-org sources are refused)" do
    setup do
      shared = persist_source!("platform-shared-source", nil, nil, :shared)
      %{shared: shared}
    end

    test "a mission operator can't disable, enable or probe a platform-shared source", c do
      for action <- ["disable-source", "probe-source", "provision-tsdb-backend"] do
        assert {:error, :platform_source} =
                 execute(request(action, %{"data-source-id" => c.shared.data_source_id}))
      end

      assert {:ok, source} = DataSources.fetch_data_source(c.shared.data_source_id)
      assert source.status == :active
    end

    test "another organization's source isn't reachable at all" do
      persist_mission_scope("org-other-tenant", "mission-other-tenant")

      persist_source!(
        "other-tenant-source",
        "org-other-tenant",
        "mission-other-tenant",
        :mission_isolated
      )

      assert {:error, :scope_mismatch} =
               execute(request("disable-source", %{"data-source-id" => "other-tenant-source"}))
    end

    test "registering an existing id never overwrites it", c do
      request =
        request("register-source", %{
          "source" => %{
            "data_source_id" => c.shared.data_source_id,
            "logical_source" => "telemetry",
            "kind" => "managed_tsdb",
            "isolation_level" => "mission_isolated",
            "credentials_ref" => "",
            "credential_provider" => "questdb",
            "endpoint_ref" => "",
            "material_env_profile" => "",
            "http_endpoint_env" => "",
            "storage" => "questdb"
          }
        })

      assert {:error, :data_source_exists} = execute(request)
      assert {:ok, source} = DataSources.fetch_data_source(c.shared.data_source_id)
      assert source.organization_id == nil
    end

    test "a platform-shared binding can't be repointed by a mission operator", c do
      {:ok, _binding} =
        DataSources.persist_data_binding(%DataBinding{
          binding_id: "platform-shared-binding",
          organization_id: nil,
          mission_id: nil,
          realm: "flight",
          logical_source: :telemetry,
          data_source_id: c.shared.data_source_id
        })

      own = persist_source!("own-source", @organization_id, @mission_id, :mission_isolated)

      assert {:error, :platform_source} =
               execute(
                 request("change-binding", %{
                   "binding" => %{
                     "binding_id" => "platform-shared-binding",
                     "data_source_id" => own.data_source_id
                   }
                 })
               )
    end

    test "a platform admin in admin mode may change a shared source", c do
      admin =
        Scope.new(%{
          user:
            User.new(%{
              user_id: "user-platform-admin-ds",
              email: "pa-ds@example.test",
              display_name: "PA",
              capabilities: [:platform_admin]
            }),
          organization_id: @organization_id,
          admin_mode?: true
        })

      assert {:ok, %DataSource{status: :disabled}} =
               DataSourcesAction.execute(
                 admin,
                 HostContext.mission(@mission_id),
                 "data_sources",
                 request("disable-source", %{"data-source-id" => c.shared.data_source_id})
               )
    end
  end

  defp execute(request),
    do:
      DataSourcesAction.execute(
        scope(),
        HostContext.mission(@mission_id),
        "data_sources",
        request
      )

  defp persist_source!(id, organization_id, mission_id, isolation) do
    {:ok, source} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: id,
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Cadence.Dashboards.Sources.Telemetry,
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: isolation,
        capabilities: %{latest?: true},
        metadata: %{storage: :questdb}
      })

    source
  end

  defp request(action_id, params) do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action_id,
      surface_id: "data_sources",
      surface_version: 1,
      params: params
    }
  end

  defp scope do
    identity = %ServiceIdentity{
      service_identity_id: "service-ops-data-sources",
      organization_id: @organization_id,
      mission_id: @mission_id,
      display_name: "Ops data sources test service",
      capabilities: [:organization_admin],
      lifecycle_state: :active
    }

    %Scope{
      actor_kind: :service,
      organization_id: @organization_id,
      mission_id: @mission_id,
      service_identity: identity,
      capabilities: MapSet.new([:organization_admin])
    }
  end
end
