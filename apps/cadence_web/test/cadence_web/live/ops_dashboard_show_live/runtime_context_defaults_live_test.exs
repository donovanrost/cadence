defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextDefaultsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, Document}
  alias Cadence.Ingress.RawEvidence
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

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
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
      Cadence.Persistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp persist_dashboard_realm!(mission, realm) do
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
               capabilities: %{range_scan?: true, latest?: true}
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

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
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

  describe "runtime context defaults" do
    test "saves and applies dashboard runtime data defaults" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Defaults")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      persist_dashboard_realm!(mission, :flight)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "dashboard-default-source-#{unique}",
          "dashboard-default-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 31, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Defaults",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?realm=rehearsal&source_binding_id=#{source_context.binding_id}"
        )

      render_dashboard_async(view)

      view
      |> element(~s(#dashboard-menu button[phx-click="save_runtime_defaults"]))
      |> render_click()

      saved_document = fetch_dashboard_document!(org, mission, dashboard)

      assert get_in(saved_document.defaults, ["data", "realm"]) == "rehearsal"

      assert get_in(saved_document.defaults, [
               "data",
               "source_contexts",
               "telemetry",
               "source_binding_id"
             ]) == source_context.binding_id

      {:ok, default_view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(default_view)

      assert has_element?(
               default_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-dashboard-source-binding-id="#{source_context.binding_id}"][data-engine-source-binding-id="#{source_context.binding_id}"])
             )

      {:ok, override_view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=flight")
      render_dashboard_async(override_view)

      assert has_element?(
               override_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="flight"])
             )

      assert has_element?(override_view, "#dashboard-active-source", "Primary source")

      {:ok, clear_view, _html} =
        live(conn, show_path(mission, dashboard) <> "?source_binding_id=primary")

      render_dashboard_async(clear_view)

      clear_view
      |> element(~s(#dashboard-menu button[phx-click="save_runtime_defaults"]))
      |> render_click()

      render_dashboard_async(view)
      render_dashboard_async(default_view)
      render_dashboard_async(override_view)
      render_dashboard_async(clear_view)

      cleared_document = fetch_dashboard_document!(org, mission, dashboard)
      assert get_in(cleared_document.defaults, ["data", "realm"]) == "rehearsal"
      assert get_in(cleared_document.defaults, ["data", "source_contexts"]) == %{}

      stop_dashboard_view(view)
      stop_dashboard_view(default_view)
      stop_dashboard_view(override_view)
      stop_dashboard_view(clear_view)
    end

    test "runtime default saves create drafts without changing published operator defaults" do
      {conn, org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "SC Published Defaults")

      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      persist_dashboard_realm!(mission, :flight)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "published-default-source-#{unique}",
          "published-default-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 41, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Published Runtime Defaults",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      assert {:ok, %Cadence.Dashboards.Version{}} =
               Cadence.Dashboards.publish_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 Document.version(dashboard),
                 expected_version: Document.version(dashboard)
               )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?realm=rehearsal&source_binding_id=#{source_context.binding_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      view
      |> element(~s(#dashboard-menu button[phx-click="save_runtime_defaults"]))
      |> render_click()

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-draft-defaults-differ="true"])
             )

      assert {:ok, published_document} =
               Cadence.Dashboards.fetch_published_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert get_in(published_document.defaults, ["data", "source_contexts"]) == nil

      draft_document = fetch_dashboard_document!(org, mission, dashboard)
      assert Document.version(draft_document) == 2

      assert get_in(draft_document.defaults, [
               "data",
               "source_contexts",
               "telemetry",
               "source_binding_id"
             ]) == source_context.binding_id

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 2
      assert summary.draft_version == 2
      assert summary.published_version == 1

      {:ok, published_view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(published_view)

      assert has_element?(
               published_view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-data-realm="flight"])
             )

      published_view |> element("#edit-layout-toggle") |> render_click()

      assert has_element?(
               published_view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"][data-dashboard-data-realm="rehearsal"][data-dashboard-source-binding-id="#{source_context.binding_id}"])
             )

      published_view |> element("#edit-layout-toggle") |> render_click()
      render_dashboard_async(published_view)

      assert has_element?(
               published_view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-data-realm="flight"])
             )
    end
  end
end
