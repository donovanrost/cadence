defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextSourceBindingLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Management.DataSources
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp value_tile(point_id, mode, spacecraft_id) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    with {:ok, result} <-
           Cadence.process_telemetry_ingress(
             evidence,
             binding_set.binding_set_id,
             binding_set.version
           ) do
      RuntimePersistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp persist_dashboard_realm!(
         mission,
         realm,
         capabilities \\ %{range_scan?: true, latest?: true}
       ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "test-#{realm}-binding-#{System.unique_integer([:positive])}",
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id}
  end

  defp persist_dashboard_realm_source!(mission, realm, data_source_id, binding_id) do
    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id, binding_id: binding_id}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp configure_telemetry_storage_source!(realm, data_source_id, binding_id) do
    previous_config = Application.get_env(:cadence, :telemetry_storage, [])

    Application.put_env(
      :cadence,
      :telemetry_storage,
      previous_config
      |> Keyword.put(:realm, realm)
      |> Keyword.put(:data_source_id, data_source_id)
      |> Keyword.put(:binding_id, binding_id)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_config)
    end)
  end

  describe "runtime context source-binding controls" do
    test "data realm control is source-binding aware" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Realm")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      _defaults = DataSources.ensure_default_managed_sources!()
      persist_dashboard_realm!(mission, :rehearsal)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Realm",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(view, ~s(#dashboard-data-realm option[value="rehearsal"]))

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-engine-data-realm="rehearsal"])
             )

      {:ok, invalid_view, _html} =
        live(conn, show_path(mission, dashboard) <> "?realm=simulation")

      render_dashboard_async(invalid_view)

      assert has_element?(
               invalid_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="flight"][data-engine-data-realm="flight"])
             )
    end

    test "runtime context control selects an explicit source binding" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Select")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      persist_dashboard_realm!(mission, :flight)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "dashboard-selector-source-#{unique}",
          "dashboard-selector-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 23, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Source Selector",
          widgets: [
            %{
              type: :time_series,
              title: "Source Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-source-binding option[value="#{source_context.binding_id}"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => "",
        "to" => "",
        "realm" => "rehearsal",
        "source_binding_id" => source_context.binding_id,
        "data_view" => "all_revisions",
        "limit_mode" => "observed"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "realm=rehearsal"
      assert patched_path =~ "data_view=all_revisions"
      assert patched_path =~ "data_source_id=#{source_context.data_source_id}"
      assert patched_path =~ "source_binding_id=#{source_context.binding_id}"

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-active-source[data-dashboard-active-data-source="#{source_context.data_source_id}"][data-dashboard-active-source-binding="#{source_context.binding_id}"]),
               source_context.binding_id
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-view="all_revisions"][data-engine-data-view="all_revisions"][data-dashboard-data-source-id="#{source_context.data_source_id}"][data-dashboard-source-binding-id="#{source_context.binding_id}"][data-engine-data-source-id="#{source_context.data_source_id}"][data-engine-source-binding-id="#{source_context.binding_id}"])
             )
    end
  end
end
