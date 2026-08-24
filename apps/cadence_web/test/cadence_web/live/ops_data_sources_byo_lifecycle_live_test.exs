defmodule CadenceWeb.OpsDataSourcesByoLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Control.DataSources, as: DataSourceControl
  alias Cadence.Control.DataSources.Probes.QuestDB
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials
  alias Cadence.Projections.DataSources.Health, as: SourceHealth
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

    {
      QuestDB.policy(
        questdb_exec_fun: questdb_probe_exec_fun(test_pid),
        questdb_timeout: 2_000
      ),
      [
        material_resolver:
          {Cadence.Management.DataSources.Credentials.EnvMaterialResolver, :resolve}
      ]
    }
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
    render_hook(view, "register_source", %{
      "source" => %{
        "data_source_id" => "customer-telemetry-questdb",
        "logical_source" => "telemetry",
        "kind" => "byo_tsdb",
        "isolation_level" => "customer_owned",
        "credentials_ref" => "cred-customer-telemetry",
        "credential_provider" => "questdb",
        "endpoint_ref" => "endpoint://customer/ops",
        "material_env_profile" => "ops-customer-questdb",
        "http_endpoint_env" => "OPS_CUSTOMER_QUESTDB_HTTP",
        "storage" => "questdb"
      }
    })
  end

  test "registers a BYO mission data source and exposes it to binding changes" do
    {conn, user, org, mission} = signed_in_org_and_mission()
    {probe_policy, credential_configuration} = configure_customer_questdb_probe!()
    persist_seed_telemetry!(org, mission)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    assert ops_data_sources_page(view)["admin"]["registration"]["id"] ==
             "register-source-panel"

    register_customer_source(view)

    source_dto = source_row(view, "customer-telemetry-questdb")
    assert source_dto["kind_text"] == "byo_tsdb"
    assert source_dto["credential_ref_text"] == "cred-customer-telemetry / active v1"

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

    rotate = source_action(view, "customer-telemetry-questdb", "rotate_source_credential")

    assert rotate["payload"] == %{
             "data-source-id" => "customer-telemetry-questdb",
             "credentials-ref" => "cred-customer-telemetry"
           }

    assert rotate["confirm"] == "Rotate this credential reference?"
    render_hook(view, "rotate_source_credential", rotate["payload"])

    source_dto = source_row(view, "customer-telemetry-questdb")
    assert source_dto["credential_version_text"] == "2"
    assert source_dto["credential_ref_text"] == "cred-customer-telemetry / active v2"

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

    assert Enum.any?(source_events(view), fn event ->
             event["event_type"] == "registered" and
               String.contains?(event["title"], "customer-telemetry-questdb")
           end)

    probe_customer_source!(user, mission, probe_policy, credential_configuration)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/customer-telemetry-questdb/settings"
      )

    assert_receive {:questdb_probe_sql, "SELECT 1", first_probe_opts}
    assert first_probe_opts[:http_endpoint] == "http://ops-customer-questdb:9000"

    assert_receive {:questdb_probe_sql, schema_sql, schema_probe_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_probe_opts[:http_endpoint] == "http://ops-customer-questdb:9000"

    source_dto = source_row(view, "customer-telemetry-questdb")
    assert source_dto["health_status"] == "healthy"
    assert source_dto["probe_kind_text"] == "adapter"
    assert source_dto["probe_metadata_text"] =~ "storage=questdb"
    assert source_dto["connection_test_result_text"] == "succeeded"
    assert source_dto["connection_test_kind_text"] == "adapter_io"

    assert source_dto["connection_test_message_text"] ==
             "Adapter connection test succeeded."

    assert source_dto["credential_material_state_text"] == "resolved"
    assert source_dto["credential_endpoint_text"] == "http://ops-customer-questdb:9000"

    assert source_dto["probe_metadata_text"] =~
             "source_capability_fingerprint=source-capability:"

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

    assert Enum.any?(source_events(view), fn event ->
             event["event_type"] == "changed" and
               String.contains?(event["title"], "customer-telemetry-questdb")
           end)

    assert {:ok, _updated_source} =
             DataSources.persist_data_source(%DataSource{
               materialized_source
               | capabilities: %{range_scan?: false}
             })

    probe_customer_source!(user, mission, probe_policy, credential_configuration)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/customer-telemetry-questdb/settings"
      )

    source_dto = source_row(view, "customer-telemetry-questdb")
    assert source_dto["probe_metadata_text"] =~ "source_capability_drift?=true"

    recovered =
      Enum.find(health_events(view), fn event -> event["event_type"] == "recovered" end)

    assert recovered["subtitle"] =~ "source_probe_succeeded"
    assert recovered["probe_kind"] == "adapter"
    assert recovered["probe_metadata"] =~ "storage=questdb"
    assert recovered["connection_test_result"] == "succeeded"
    assert recovered["connection_test_kind"] == "adapter_io"
    assert recovered["probe_metadata"] =~ "source_capability_fingerprint=source-capability:"

    disable = source_action(view, "customer-telemetry-questdb", "disable_source")
    assert disable["payload"] == %{"data-source-id" => "customer-telemetry-questdb"}
    assert disable["confirm"] == "Disable this data source?"
    render_hook(view, "disable_source", disable["payload"])

    assert source_row(view, "customer-telemetry-questdb")["status_text"] == "disabled"

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

    render_hook(view, "open_change_binding", %{"binding-id" => "flight-telemetry-binding"})
    refute "customer-telemetry-questdb" in binding_option_values(view)

    render_hook(view, "cancel_change_binding", %{})
    assert ops_data_sources_page(view)["admin"]["binding_form"] == nil

    enable = source_action(view, "customer-telemetry-questdb", "enable_source")
    assert enable["payload"] == %{"data-source-id" => "customer-telemetry-questdb"}
    render_hook(view, "enable_source", enable["payload"])

    assert source_row(view, "customer-telemetry-questdb")["status_text"] == "active"

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

    render_hook(view, "open_change_binding", %{"binding-id" => "flight-telemetry-binding"})
    assert "customer-telemetry-questdb" in binding_option_values(view)
  end

  defp questdb_probe_exec_fun(test_pid) do
    fn sql, opts ->
      send(test_pid, {:questdb_probe_sql, sql, opts})
      questdb_probe_response(sql)
    end
  end

  defp probe_customer_source!(user, mission, probe_policy, credential_configuration) do
    assert {:ok, _event_or_unchanged, _status} =
             DataSourceControl.probe(
               "customer-telemetry-questdb",
               %{mission_id: mission.mission_id},
               actor_id: user.user_id,
               credential_configuration: credential_configuration,
               env_reader: fn "OPS_CUSTOMER_QUESTDB_HTTP" ->
                 "http://ops-customer-questdb:9000"
               end,
               materialize_adapter_capabilities?: true,
               payload: %{source: "ops_data_sources_live"},
               questdb_probe?: true,
               data_source_probe_policy: probe_policy
             )
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

  defp ops_data_sources_page(view_or_html) do
    view_or_html
    |> LiveVue.Test.get_vue(id: "ops-data-sources-component")
    |> then(& &1.props["page"])
  end

  defp source_row(view_or_html, data_source_id) do
    Enum.find(
      ops_data_sources_page(view_or_html)["sources"]["rows"],
      &(&1["data_source_id"] == data_source_id)
    )
  end

  defp source_action(view_or_html, data_source_id, event) do
    view_or_html
    |> source_row(data_source_id)
    |> Map.get("actions", [])
    |> Enum.find(&(&1["event"] == event))
  end

  defp source_events(view_or_html) do
    ops_data_sources_page(view_or_html)["activity"]["source_events"]["rows"]
  end

  defp health_events(view_or_html) do
    ops_data_sources_page(view_or_html)["activity"]["health_events"]["rows"]
  end

  defp binding_option_values(view_or_html) do
    view_or_html
    |> ops_data_sources_page()
    |> get_in(["admin", "binding_form", "source_options"])
    |> Enum.map(& &1["value"])
  end
end
