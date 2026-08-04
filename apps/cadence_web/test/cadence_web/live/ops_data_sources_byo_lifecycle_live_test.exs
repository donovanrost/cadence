defmodule CadenceWeb.OpsDataSourcesByoLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.Management.DataSources

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow}
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")

    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp configure_customer_questdb_probe! do
    test_pid = self()
    previous_credential_config = Application.get_env(:cadence, :data_source_credentials, [])
    previous_probe_config = Application.get_env(:cadence, :data_source_probe, [])

    System.put_env("OPS_CUSTOMER_QUESTDB_HTTP", "http://ops-customer-questdb:9000")

    Application.put_env(
      :cadence,
      :data_source_credentials,
      Keyword.merge(previous_credential_config,
        material_resolver:
          {Cadence.Management.DataSources.Credentials.EnvMaterialResolver, :resolve}
      )
    )

    Application.put_env(
      :cadence,
      :data_source_probe,
      Keyword.merge(previous_probe_config,
        questdb_exec_fun: questdb_probe_exec_fun(test_pid)
      )
    )

    on_exit(fn ->
      Application.put_env(:cadence, :data_source_credentials, previous_credential_config)
      Application.put_env(:cadence, :data_source_probe, previous_probe_config)
      System.delete_env("OPS_CUSTOMER_QUESTDB_HTTP")
    end)
  end

  defp persist_seed_telemetry!(org, mission) do
    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "seed-telemetry",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "flight-telemetry-binding",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "seed-telemetry",
               dataset: "flight",
               priority: 0
             })
  end

  defp register_customer_source(view) do
    view
    |> form("#register-source-form",
      source: %{
        data_source_id: "customer-telemetry-questdb",
        logical_source: "telemetry",
        kind: "byo_tsdb",
        isolation_level: "customer_owned",
        credentials_ref: "cred-customer-telemetry",
        credential_provider: "questdb",
        endpoint_ref: "endpoint://customer/ops",
        material_env_profile: "ops-customer-questdb",
        http_endpoint_env: "OPS_CUSTOMER_QUESTDB_HTTP",
        storage: "questdb"
      }
    )
    |> render_submit()
  end

  test "registers a BYO mission data source and exposes it to binding changes" do
    {conn, user, org, mission} = signed_in_org_and_mission()
    configure_customer_questdb_probe!()
    persist_seed_telemetry!(org, mission)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    assert has_element?(view, "#register-source-panel")

    register_customer_source(view)

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-data-source-row="customer-telemetry-questdb"]),
             "byo_tsdb"
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb),
             "cred-customer-telemetry / active v1"
           )

    assert {:ok, reference} = SourceCredentials.fetch_reference("cred-customer-telemetry")
    assert reference.organization_id == org.organization_id
    assert reference.mission_id == mission.mission_id
    assert reference.data_source_id == "customer-telemetry-questdb"
    assert reference.owner == :customer
    assert reference.kind == :byo_tsdb_connection
    assert reference.provider == "questdb"
    assert reference.metadata["endpoint_ref"] == "endpoint://customer/ops"
    assert reference.metadata["material_env_profile"] == "ops-customer-questdb"
    assert reference.metadata["http_endpoint_env"] == "OPS_CUSTOMER_QUESTDB_HTTP"

    assert [credential_event] = SourceCredentials.list_events("cred-customer-telemetry")
    assert credential_event.actor_id == user.user_id
    assert credential_event.payload["source"] == "ops_data_sources_live"

    view
    |> element("#rotate-credential-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-credential-version="2"]),
             "cred-customer-telemetry / active v2"
           )

    assert {:ok, rotated_reference} =
             SourceCredentials.fetch_reference("cred-customer-telemetry")

    assert rotated_reference.credential_version == 2
    assert rotated_reference.status == :active
    assert rotated_reference.data_source_id == "customer-telemetry-questdb"
    assert rotated_reference.last_rotated_at

    assert [rotated_event, registered_event] =
             SourceCredentials.list_events("cred-customer-telemetry")

    assert rotated_event.event_type == :rotated
    assert rotated_event.actor_id == user.user_id
    assert rotated_event.previous_credential_version == 1
    assert rotated_event.current_credential_version == 2
    assert rotated_event.payload["source"] == "ops_data_sources_live"
    assert rotated_event.payload["data_source_id"] == "customer-telemetry-questdb"
    assert registered_event.event_type == :registered

    assert %DataSource{} =
             source =
             org.organization_id
             |> DataSources.list_data_sources(mission.mission_id)
             |> Enum.find(&(&1.data_source_id == "customer-telemetry-questdb"))

    assert source.adapter == Cadence.Dashboards.Sources.Telemetry
    assert source.isolation_level == :customer_owned
    assert source.credentials_ref == "cred-customer-telemetry"
    assert source.metadata["storage"] == "questdb"
    assert source.metadata["endpoint_ref"] == "endpoint://customer/ops"
    assert source.metadata["material_env_profile"] == "ops-customer-questdb"

    assert [source_event] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert source_event.event_type == :registered
    assert source_event.actor_id == user.user_id
    assert source_event.payload["source"] == "ops_data_sources_live"
    assert source_event.payload["storage"] == "questdb"

    assert has_element?(
             view,
             ~s(#dashboard-data-source-events [data-event-type="registered"]),
             "customer-telemetry-questdb"
           )

    view
    |> element("#probe-source-customer-telemetry-questdb")
    |> render_click()

    assert_receive {:questdb_probe_sql, "SELECT 1", first_probe_opts}
    assert first_probe_opts[:http_endpoint] == "http://ops-customer-questdb:9000"

    assert_receive {:questdb_probe_sql, schema_sql, schema_probe_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_probe_opts[:http_endpoint] == "http://ops-customer-questdb:9000"

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-health="healthy"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-probe-kind="adapter"][data-source-probe-metadata*="storage=questdb"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-connection-test-result="succeeded"][data-source-connection-test-kind="adapter_io"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb),
             "Adapter connection test succeeded."
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-credential-material-state="resolved"][data-source-credential-endpoint="http://ops-customer-questdb:9000"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-probe-metadata*="source_capability_fingerprint=source-capability:"])
           )

    assert {:ok, %DataSource{} = materialized_source} =
             DataSources.fetch_data_source("customer-telemetry-questdb")

    assert materialized_source.capabilities["native_decimation?"] == true
    assert materialized_source.capabilities["watermarks?"] == true
    assert materialized_source.metadata["adapter_capability_discovery?"] == true
    assert materialized_source.metadata["adapter_capability_discovery_source"] == "probe"

    assert materialized_source.metadata["adapter_capability_discovery_fingerprint"] =~
             "source-capability:"

    assert [health_status] =
             SourceHealth.list_source_health_statuses(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert health_status.source_health == :healthy
    assert health_status.reason == :source_probe_succeeded
    assert health_status.payload["source"] == "ops_data_sources_live"
    assert health_status.payload["probe_kind"] == "adapter"
    assert health_status.payload["actor_id"] == user.user_id
    assert health_status.payload["connection_test_result"] == "succeeded"
    assert health_status.payload["connection_test_kind"] == "adapter_io"

    assert source_events =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert materialized_event =
             Enum.find(source_events, fn event ->
               event.event_type == :changed and
                 event.payload["adapter_capability_discovery?"] == true
             end)

    assert materialized_event.actor_id == user.user_id
    assert materialized_event.payload["source"] == "data_source_probe"

    assert materialized_event.payload["source_health_event_id"] ==
             health_status.source_health_event_id

    assert materialized_event.current_capabilities["native_decimation?"] == true

    assert has_element?(
             view,
             ~s(#dashboard-data-source-events [data-event-type="changed"]),
             "customer-telemetry-questdb"
           )

    assert {:ok, _updated_source} =
             DataSources.persist_data_source(%DataSource{
               materialized_source
               | capabilities: %{range_scan?: false}
             })

    view
    |> element("#probe-source-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-probe-metadata*="source_capability_drift?=true"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"]),
             "source_probe_succeeded"
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"][data-event-probe-kind="adapter"][data-event-probe-metadata*="storage=questdb"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"][data-event-connection-test-result="succeeded"][data-event-connection-test-kind="adapter_io"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"][data-event-probe-metadata*="source_capability_fingerprint=source-capability:"])
           )

    view
    |> element("#disable-source-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-status="disabled"])
           )

    assert {:ok, disabled_source} = DataSources.fetch_data_source("customer-telemetry-questdb")
    assert disabled_source.status == :disabled
    assert disabled_source.disabled_at

    assert [disabled_event | _events] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert disabled_event.event_type == :disabled
    assert disabled_event.actor_id == user.user_id
    assert disabled_event.payload["source"] == "ops_data_sources_live"

    view
    |> element("#change-binding-flight-telemetry-binding")
    |> render_click()

    refute has_element?(
             view,
             ~s(#change-binding-form-flight-telemetry-binding option[value="customer-telemetry-questdb"])
           )

    view
    |> element("#cancel-change-binding-flight-telemetry-binding")
    |> render_click()

    view
    |> element("#enable-source-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-status="active"])
           )

    assert {:ok, enabled_source} = DataSources.fetch_data_source("customer-telemetry-questdb")
    assert enabled_source.status == :active
    assert enabled_source.disabled_at == nil

    assert [enabled_event | _events] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert enabled_event.event_type == :enabled
    assert enabled_event.actor_id == user.user_id
    assert enabled_event.payload["source"] == "ops_data_sources_live"

    view
    |> element("#change-binding-flight-telemetry-binding")
    |> render_click()

    assert has_element?(
             view,
             ~s(#change-binding-form-flight-telemetry-binding option[value="customer-telemetry-questdb"])
           )
  end

  defp questdb_probe_exec_fun(test_pid) do
    fn sql, opts ->
      send(test_pid, {:questdb_probe_sql, sql, opts})
      questdb_probe_response(sql)
    end
  end

  defp questdb_probe_response("SELECT 1"),
    do: {:ok, %{"columns" => [%{"name" => "1"}], "dataset" => [[1]]}}

  defp questdb_probe_response(sql) do
    if String.contains?(sql, "FROM telemetry_observations") do
      {:ok, %{"columns" => questdb_probe_columns(), "dataset" => []}}
    else
      flunk("Unexpected QuestDB probe SQL:\n#{sql}")
    end
  end

  defp questdb_probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
    |> Enum.map(&%{"name" => &1})
  end
end
