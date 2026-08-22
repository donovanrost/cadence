defmodule Cadence.Dashboards.DataSourcesCredentialsTest do
  use Cadence.DataCase, async: true

  import Cadence.DataSourcesFixtures

  alias Cadence.Control.DataSources, as: DataSourceControl
  alias Cadence.Control.DataSources.Probes.QuestDB

  alias Cadence.Dashboards.{
    DataSourceRegistry,
    SourceExecutionPolicy,
    SourceRegistry,
    SourceResult
  }

  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  @organization_id "org-dash-source-credentials"
  @mission_id "mission-dash-source-credentials"
  @event_bus __MODULE__.UnusedEventBus

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "QuestDB telemetry probes classify authentication failures separately" do
    data_source = %DataSource{
      data_source_id: "questdb-auth-failed",
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :customer_owned,
      credentials_ref: "secret://#{@organization_id}/dashboard/customer-auth-failed",
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: data_source.credentials_ref,
               organization_id: data_source.organization_id,
               mission_id: data_source.mission_id,
               data_source_id: data_source.data_source_id,
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb"
             })

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    assert {:ok, unavailable_event, _unavailable_status} =
             DataSourceControl.probe(
               "questdb-auth-failed",
               %{observed_at: ~U[2026-06-21 22:23:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               data_source_probe_policy: QuestDB.policy([]),
               credential_material_resolver: fn _credential, _opts ->
                 {:ok,
                  %{
                    http_endpoint: "https://customer-questdb.example.test",
                    bearer_token: "secret-token"
                  }}
               end,
               questdb_exec_fun: questdb_probe_exec_fun(self(), :auth_error),
               credential_configuration: %{},
               event_bus: @event_bus,
               invalidate_runtime_cache?: false
             )

    assert_receive {:questdb_probe_sql, "SELECT 1"}

    metadata = unavailable_event.payload["probe_metadata"]
    assert unavailable_event.source_health == :unavailable
    assert unavailable_event.reason == :source_connection_failed
    assert metadata["probe_diagnostic_kind"] == "authentication_failed"
    assert metadata["probe_diagnostic_stage"] == "connection_test"
    assert metadata["probe_remediation"] == "check_credential_material"
    assert metadata["adapter_error"] =~ "http_error"
    refute inspect(unavailable_event) =~ "secret-token"
  end

  test "persists customer-owned BYO data sources with indirect credential refs" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref:
                 "secret://#{@organization_id}/dashboard/customer-rehearsal-questdb",
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "customer-rehearsal-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/rehearsal"}
             })

    data_source = %DataSource{
      data_source_id: "customer-rehearsal-questdb",
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :customer_owned,
      credentials_ref: "secret://#{@organization_id}/dashboard/customer-rehearsal-questdb",
      capabilities: %{range_scan?: true, watermarks?: false},
      metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/rehearsal"}
    }

    assert {:ok, persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)
    assert persisted.owner == :customer
    assert persisted.kind == :byo_tsdb
    assert persisted.isolation_level == :customer_owned

    assert persisted.credentials_ref ==
             "secret://#{@organization_id}/dashboard/customer-rehearsal-questdb"

    assert persisted.metadata["endpoint_ref"] == "endpoint://customer/rehearsal"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "customer-rehearsal-telemetry",
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 realm: :rehearsal,
                 logical_source: :telemetry,
                 data_source_id: "customer-rehearsal-questdb",
                 dataset: "rehearsal-12",
                 priority: 0
               },
               event_bus: @event_bus
             )

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(
               source_request_for_scope(data_context: %{realm: :rehearsal}),
               persisted?: true
             )

    assert resolved.data_source.data_source_id == "customer-rehearsal-questdb"
    assert resolved.data_source.credentials_ref == persisted.credentials_ref
    assert resolved.data_source.metadata["endpoint_ref"] == "endpoint://customer/rehearsal"
    refute Map.has_key?(resolved.data_source.metadata, "password")
  end

  test "BYO QuestDB probes use redacted credential connection profiles" do
    credentials_ref = "secret://#{@organization_id}/dashboard/byo-probe-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "byo-probe-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{
                 endpoint_ref: "endpoint://customer/rehearsal",
                 http_endpoint: "http://customer-questdb:9000"
               }
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(
               %DataSource{
                 data_source_id: "byo-probe-questdb",
                 owner: :customer,
                 kind: :byo_tsdb,
                 adapter: Cadence.Dashboards.Sources.Telemetry,
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 isolation_level: :customer_owned,
                 credentials_ref: credentials_ref,
                 capabilities: %{range_scan?: true, watermarks?: true},
                 metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/rehearsal"}
               },
               event_bus: @event_bus
             )

    test_pid = self()

    assert {:ok, healthy_event, healthy_status} =
             DataSourceControl.probe(
               "byo-probe-questdb",
               %{observed_at: ~U[2026-06-21 22:25:00Z]},
               actor_id: "operator-byo-questdb",
               questdb_probe?: true,
               data_source_probe_policy:
                 QuestDB.policy(
                   questdb_exec_fun: questdb_probe_exec_with_opts_fun(test_pid, :schema_ok),
                   questdb_timeout: 1_234
                 ),
               credential_configuration: %{},
               event_bus: @event_bus,
               invalidate_runtime_cache?: false
             )

    assert_receive {:questdb_probe_sql, "SELECT 1", questdb_opts}
    assert questdb_opts[:http_endpoint] == "http://customer-questdb:9000"
    assert questdb_opts[:timeout] == 1_234

    assert_receive {:questdb_probe_sql, schema_sql, schema_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_opts[:http_endpoint] == "http://customer-questdb:9000"

    metadata = healthy_event.payload["probe_metadata"]
    profile = metadata["source_connection_profile"]

    assert healthy_event.source_health == :healthy
    assert healthy_status.source_health == :healthy
    assert healthy_event.payload["connection_test_result"] == "succeeded"
    assert healthy_event.payload["connection_test_kind"] == "adapter_io"
    assert metadata["http_endpoint"] == "http://customer-questdb:9000"
    assert metadata["connection_profile?"] == true
    assert profile["credentials_ref"] == credentials_ref
    assert profile["credential_provider"] == "questdb"
    assert profile["credential_kind"] == "byo_tsdb_connection"
    assert profile["credential_owner"] == "customer"
    assert profile["credential_version"] == 1
    assert profile["credential_status"] == "active"
    assert profile["data_source_id"] == "byo-probe-questdb"
    assert profile["data_source_kind"] == "byo_tsdb"
    assert profile["data_source_owner"] == "customer"
    assert profile["isolation_level"] == "customer_owned"
    assert profile["physical_isolation"]["isolation_level"] == "customer_owned"
    assert profile["physical_isolation"]["physical_boundary"] == "customer_connection"
    assert profile["physical_isolation"]["organization_id"] == @organization_id
    assert profile["physical_isolation"]["mission_id"] == @mission_id
    assert profile["physical_isolation"]["storage"] == "questdb"
    assert profile["physical_isolation"]["endpoint_ref"] == "endpoint://customer/rehearsal"
    assert profile["endpoint_ref"] == "endpoint://customer/rehearsal"
    assert profile["http_endpoint"] == "http://customer-questdb:9000"
    assert profile["secret_material?"] == false
    refute Map.has_key?(profile, "password")
    refute Map.has_key?(profile, "token")
  end

  test "BYO QuestDB probes use resolved credential material without persisting secrets" do
    credentials_ref = "secret://#{@organization_id}/dashboard/byo-material-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "byo-material-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/material"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(
               %DataSource{
                 data_source_id: "byo-material-questdb",
                 owner: :customer,
                 kind: :byo_tsdb,
                 adapter: Cadence.Dashboards.Sources.Telemetry,
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 isolation_level: :customer_owned,
                 credentials_ref: credentials_ref,
                 capabilities: %{range_scan?: true, watermarks?: true},
                 metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/material"}
               },
               event_bus: @event_bus
             )

    resolver = fn credential, opts ->
      assert credential.credentials_ref == credentials_ref
      assert Keyword.fetch!(opts, :organization_id) == @organization_id
      assert Keyword.fetch!(opts, :mission_id) == @mission_id
      assert Keyword.fetch!(opts, :data_source_id) == "byo-material-questdb"

      {:ok,
       %{
         http_endpoint: "http://secret-material-questdb:9000",
         username: "quest-user",
         password: "quest-password"
       }}
    end

    test_pid = self()

    assert {:ok, healthy_event, healthy_status} =
             DataSourceControl.probe(
               "byo-material-questdb",
               %{observed_at: ~U[2026-06-27 20:05:00Z]},
               actor_id: "operator-byo-questdb",
               credential_material_resolver: resolver,
               questdb_probe?: true,
               data_source_probe_policy: QuestDB.policy([]),
               questdb_exec_fun: questdb_probe_exec_with_opts_fun(test_pid, :schema_ok),
               credential_configuration: %{},
               event_bus: @event_bus,
               invalidate_runtime_cache?: false
             )

    expected_auth = "Basic " <> Base.encode64("quest-user:quest-password")

    assert_receive {:questdb_probe_sql, "SELECT 1", questdb_opts}
    assert questdb_opts[:http_endpoint] == "http://secret-material-questdb:9000"
    assert {"authorization", expected_auth} in questdb_opts[:headers]

    assert_receive {:questdb_probe_sql, schema_sql, schema_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_opts[:http_endpoint] == "http://secret-material-questdb:9000"
    assert {"authorization", expected_auth} in schema_opts[:headers]

    metadata = healthy_event.payload["probe_metadata"]
    profile = metadata["source_connection_profile"]

    assert healthy_event.source_health == :healthy
    assert healthy_status.source_health == :healthy
    assert healthy_event.payload["connection_test_result"] == "succeeded"
    assert metadata["http_endpoint"] == "http://secret-material-questdb:9000"
    assert profile["secret_material?"] == true
    assert profile["secret_material_fields"] == ["username", "password"]
    assert profile["http_endpoint"] == "http://secret-material-questdb:9000"
    refute Map.has_key?(profile, "username")
    refute Map.has_key?(profile, "password")
    refute inspect(healthy_event.payload) =~ "quest-password"
    refute inspect(healthy_event.payload) =~ expected_auth
  end

  test "BYO QuestDB source execution uses resolved credential material without exposing secrets" do
    credentials_ref = "secret://#{@organization_id}/dashboard/byo-exec-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "byo-exec-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/execution"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(
               %DataSource{
                 data_source_id: "byo-exec-questdb",
                 owner: :customer,
                 kind: :byo_tsdb,
                 adapter: Cadence.Dashboards.Sources.Telemetry,
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 isolation_level: :customer_owned,
                 credentials_ref: credentials_ref,
                 capabilities: %{latest?: true, range_scan?: true},
                 metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/execution"}
               },
               event_bus: @event_bus
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "byo-exec-flight",
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 realm: :flight,
                 logical_source: :telemetry,
                 data_source_id: "byo-exec-questdb",
                 dataset: "flight",
                 priority: 0
               },
               event_bus: @event_bus
             )

    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:byo_latest_opts, organization_id, mission_id, point_id, opts})

      sample(point_id, "sample-byo-exec", 42.0, ~U[2026-06-27 20:10:00Z], "evidence-byo",
        mission_id: @mission_id
      )
    end

    backend = fn credential, opts ->
      assert credential.credentials_ref == credentials_ref
      assert Keyword.fetch!(opts, :organization_id) == @organization_id
      assert Keyword.fetch!(opts, :mission_id) == @mission_id
      assert Keyword.fetch!(opts, :data_source_id) == "byo-exec-questdb"

      {:ok,
       %{
         http_endpoint: "http://secret-exec-questdb:9000",
         bearer_token: "execution-token",
         headers: [{"x-tenant", "customer-a"}]
       }}
    end

    result =
      SourceRegistry.resolve(
        source_request_for_scope(sampling: %{mode: :latest}),
        persisted?: true,
        source_execution_defaults: SourceExecutionPolicy.default(),
        source_circuit_breaker?: false,
        source_health_events?: false,
        source_watermark_events?: false,
        credential_configuration: %{},
        credential_material_authorizer: fn credential, opts ->
          send(parent, {:byo_material_authorized, credential.credentials_ref, opts})
          :ok
        end,
        credential_secret_backend: backend,
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert %SourceResult{frames: [_frame], warnings: warnings} = result
    refute result.meta.degraded?
    refute Enum.any?(warnings, &(&1.code == :source_unavailable))

    assert_receive {:byo_latest_opts, @organization_id, @mission_id, "HK.counter", opts}

    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "byo-exec-questdb"
    assert opts[:source_binding_id] == "byo-exec-flight"
    assert opts[:dataset] == "flight"
    assert opts[:http_endpoint] == "http://secret-exec-questdb:9000"
    assert {"authorization", "Bearer execution-token"} in opts[:headers]
    assert {"x-tenant", "customer-a"} in opts[:headers]

    profile = Keyword.fetch!(opts, :source_connection_profile)
    assert profile.secret_material? == true
    assert profile.secret_material_fields == ["bearer_token", "headers"]
    assert profile.http_endpoint == "http://secret-exec-questdb:9000"
    assert profile.data_source_id == "byo-exec-questdb"
    refute Map.has_key?(profile, :bearer_token)
    refute Map.has_key?(profile, :headers)
    refute inspect(result) =~ "execution-token"

    assert_receive {:byo_material_authorized, ^credentials_ref, authz_opts}
    assert Keyword.fetch!(authz_opts, :organization_id) == @organization_id
    assert Keyword.fetch!(authz_opts, :mission_id) == @mission_id
    assert Keyword.fetch!(authz_opts, :data_source_id) == "byo-exec-questdb"
  end

  test "BYO QuestDB source execution fails closed when credential material cannot resolve" do
    credentials_ref = "secret://#{@organization_id}/dashboard/byo-exec-missing-material"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "byo-exec-missing-material",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/missing-material"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(
               %DataSource{
                 data_source_id: "byo-exec-missing-material",
                 owner: :customer,
                 kind: :byo_tsdb,
                 adapter: Cadence.Dashboards.Sources.Telemetry,
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 isolation_level: :customer_owned,
                 credentials_ref: credentials_ref,
                 capabilities: %{latest?: true, range_scan?: true},
                 metadata: %{
                   storage: :questdb,
                   endpoint_ref: "endpoint://customer/missing-material"
                 }
               },
               event_bus: @event_bus
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "byo-exec-missing-material-flight",
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 realm: :flight,
                 logical_source: :telemetry,
                 data_source_id: "byo-exec-missing-material",
                 dataset: "flight",
                 priority: 0
               },
               event_bus: @event_bus
             )

    result =
      SourceRegistry.resolve(
        source_request_for_scope(sampling: %{mode: :latest}),
        persisted?: true,
        source_execution_defaults: SourceExecutionPolicy.default(),
        source_circuit_breaker?: false,
        source_health_events?: false,
        source_watermark_events?: false,
        credential_configuration: %{},
        credential_material_resolver: fn _credential, _opts -> {:error, :vault_unavailable} end
      )

    assert %SourceResult{frames: [], warnings: [warning]} = result
    assert result.meta.degraded?
    assert warning.code == :source_unavailable
    assert warning.details.data_source_id == "byo-exec-missing-material"
    assert warning.details.binding_id == "byo-exec-missing-material-flight"
    assert warning.details.reason =~ "vault_unavailable"
  end

  test "rejects BYO data sources with unregistered credential refs" do
    data_source = %DataSource{
      data_source_id: "dangling-credential-questdb",
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :customer_owned,
      credentials_ref: "secret://#{@organization_id}/dashboard/missing",
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:error, :credential_reference_not_found} =
             DataSources.persist_data_source(data_source, event_bus: @event_bus)
  end

  defp source_request_for_scope(overrides) do
    source_request(
      Keyword.merge(
        [organization_id: @organization_id, mission_id: @mission_id],
        overrides
      )
    )
  end
end
