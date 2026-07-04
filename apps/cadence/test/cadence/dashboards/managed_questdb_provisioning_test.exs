defmodule Cadence.Dashboards.ManagedQuestDBProvisioningTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{DataSource, DataSources, ManagedQuestDBProvisioning}

  @organization_id "org-managed-questdb-provisioning"
  @mission_id "mission-managed-questdb-provisioning"
  @data_source_id "mission-managed-questdb-provisioned"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "plans a mission-isolated managed QuestDB source without exposing connection secrets" do
    assert {:ok, plan} =
             ManagedQuestDBProvisioning.plan(
               attrs(%{
                 http_endpoint: "http://mission-questdb:9000",
                 password: "quest-password"
               }),
               migrations_path: "/tmp/cadence-questdb-migrations"
             )

    assert %DataSource{} = plan.data_source
    assert plan.data_source.data_source_id == @data_source_id
    assert plan.data_source.owner == :cadence
    assert plan.data_source.kind == :managed_tsdb
    assert plan.data_source.organization_id == @organization_id
    assert plan.data_source.mission_id == @mission_id
    assert plan.data_source.isolation_level == :mission_isolated
    assert plan.data_source.metadata.endpoint_ref == "endpoint://cadence/mission-questdb"
    assert plan.data_source.metadata.topology_ref == "topology://cadence/mission-questdb"
    assert plan.isolation_profile.physical_boundary == :mission
    assert plan.connection_config[:http_endpoint] == "http://mission-questdb:9000"
    assert plan.connection_config[:secret_material?]
    refute Keyword.has_key?(plan.connection_config, :password)
    refute Keyword.has_key?(plan.connection_config, :exec_fun)
    refute inspect(plan) =~ "quest-password"
  end

  test "provisions a managed QuestDB source after applying schema migrations" do
    migration = migration("20260630010101", "create_observations")

    migrator = fn migration_config ->
      assert migration_config[:http_endpoint] == "http://mission-questdb:9000"
      assert migration_config[:migrations_path] =~ "questdb/migrations"
      {:ok, [migration]}
    end

    assert {:ok, result} =
             ManagedQuestDBProvisioning.provision(
               attrs(%{http_endpoint: "http://mission-questdb:9000"}),
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-30 15:00:00Z],
               migrator: migrator
             )

    assert result.applied_migrations == [migration]
    assert result.isolation_profile.physical_boundary == :mission
    assert result.provisioning.applied_migration_versions == ["20260630010101"]

    assert {:ok, persisted} = DataSources.fetch_data_source(@data_source_id)
    assert persisted.data_source_id == @data_source_id
    assert persisted.metadata["storage"] == "questdb"
    assert persisted.metadata["provisioning"]["provisioner"] == "managed_questdb"
    assert persisted.metadata["provisioning"]["applied_migration_count"] == 1
    refute inspect(persisted) =~ "mission-questdb:9000"

    assert [event] =
             DataSources.list_data_source_events(@organization_id, @mission_id,
               data_source_id: @data_source_id
             )

    assert event.event_type == :registered
    assert event.actor_id == "operator-1"
    assert event.occurred_at == ~U[2026-06-30 15:00:00.000000Z]
    assert event.payload["kind"] == "managed_questdb_provisioned"
    assert event.payload["physical_isolation"]["physical_boundary"] == "mission"
    assert event.payload["provisioning"]["applied_migration_versions"] == ["20260630010101"]
    refute inspect(event.payload) =~ "mission-questdb:9000"
  end

  test "does not persist a data source when schema migration fails" do
    migrator = fn _migration_config -> {:error, :questdb_unavailable} end

    assert {:error, :questdb_unavailable} =
             ManagedQuestDBProvisioning.provision(
               attrs(%{data_source_id: "mission-managed-questdb-failed"}),
               migrator: migrator
             )

    assert {:error, :data_source_not_found} =
             DataSources.fetch_data_source("mission-managed-questdb-failed")
  end

  test "rejects unsupported and underscoped managed QuestDB isolation levels" do
    assert {:error, {:unsupported_managed_questdb_isolation_level, :shared}} =
             ManagedQuestDBProvisioning.plan(attrs(%{isolation_level: :shared}))

    assert {:error, {:required_managed_questdb_field_missing, :mission_id}} =
             ManagedQuestDBProvisioning.plan(
               attrs(%{data_source_id: "missing-mission", mission_id: nil})
             )
  end

  test "plans an org-isolated managed QuestDB source without mission scope" do
    assert {:ok, plan} =
             ManagedQuestDBProvisioning.plan(
               attrs(%{
                 data_source_id: "org-managed-questdb-provisioned",
                 isolation_level: :org_isolated,
                 mission_id: nil,
                 endpoint_ref: "endpoint://cadence/org-questdb"
               })
             )

    assert plan.data_source.organization_id == @organization_id
    assert plan.data_source.mission_id == nil
    assert plan.data_source.isolation_level == :org_isolated
    assert plan.isolation_profile.physical_boundary == :organization
  end

  defp attrs(overrides) do
    %{
      data_source_id: @data_source_id,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      endpoint_ref: "endpoint://cadence/mission-questdb",
      topology_ref: "topology://cadence/mission-questdb"
    }
    |> Map.merge(overrides)
  end

  defp migration(version, name) do
    %{
      version: version,
      name: name,
      path: "/tmp/#{version}_#{name}.sql",
      sql: "SELECT 1",
      checksum: "checksum-#{version}"
    }
  end
end
