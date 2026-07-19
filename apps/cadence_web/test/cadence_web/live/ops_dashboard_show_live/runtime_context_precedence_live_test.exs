defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextPrecedenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, Document}
  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  test "runtime context precedence composes document defaults URL params and live controls" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Precedence")
    binding_set = persist_binding_set!(org, mission)
    unique = System.unique_integer([:positive])

    rehearsal_source =
      persist_dashboard_realm_source!(
        mission,
        :rehearsal,
        "precedence-rehearsal-source-#{unique}",
        "precedence-rehearsal-binding-#{unique}"
      )

    replay_source =
      persist_dashboard_realm_source!(
        mission,
        :replay,
        "precedence-replay-source-#{unique}",
        "precedence-replay-binding-#{unique}"
      )

    configure_telemetry_storage_source!(
      :rehearsal,
      rehearsal_source.data_source_id,
      rehearsal_source.binding_id
    )

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 17, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Runtime Precedence",
        widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn document ->
        %Document{} = document

        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "rehearsal",
                "view" => "all_revisions",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "telemetry" => %{
                    "source_binding_id" => rehearsal_source.binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    {:ok, defaults_view, _html} = live(conn, show_path(mission, document))
    render_dashboard_async(defaults_view)

    assert has_element?(
             defaults_view,
             ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-dashboard-data-view="all_revisions"][data-dashboard-source-binding-id="#{rehearsal_source.binding_id}"][data-engine-data-realm="rehearsal"][data-engine-data-view="all_revisions"][data-engine-source-binding-id="#{rehearsal_source.binding_id}"])
           )

    replay_query =
      URI.encode_query(%{
        scope_kind: "mission",
        scope_id: mission.mission_id,
        time_mode: "replay_run",
        time_axis: "receipt_time",
        replay_run_id: "replay-precedence-1",
        source_binding_id: replay_source.binding_id,
        data_view: "as_recorded",
        compare_data_view: "canonical",
        limit_mode: "current"
      })

    {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?#{replay_query}")
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"][data-dashboard-time-mode="replay_run"][data-dashboard-time-axis="receipt_time"][data-dashboard-replay-run-id="replay-precedence-1"][data-dashboard-data-realm="replay"][data-dashboard-data-view="as_recorded"][data-dashboard-compare-data-view="canonical"][data-dashboard-source-binding-id="#{replay_source.binding_id}"][data-dashboard-limit-mode="current"][data-engine-time-mode="replay_run"][data-engine-time-axis="receipt_time"][data-engine-replay-run-id="replay-precedence-1"][data-engine-data-realm="replay"][data-engine-data-view="as_recorded"][data-engine-source-binding-id="#{replay_source.binding_id}"][data-engine-limit-mode="current"])
           )

    view
    |> element("#runtime-context-form")
    |> render_change(%{
      "time_mode" => "live",
      "time_axis" => "generation_time",
      "from" => "",
      "to" => "",
      "realm" => "rehearsal",
      "source_binding_id" => rehearsal_source.binding_id,
      "data_view" => "canonical",
      "compare_data_view" => "",
      "limit_mode" => "observed"
    })

    patched_path = assert_patch(view)
    assert patched_path =~ "scope_kind=mission"
    assert patched_path =~ "scope_id=#{mission.mission_id}"
    assert patched_path =~ "data_view=canonical"
    assert patched_path =~ "data_source_id=#{rehearsal_source.data_source_id}"
    assert patched_path =~ "source_binding_id=#{rehearsal_source.binding_id}"
    refute patched_path =~ "realm="
    refute patched_path =~ "time_mode="
    refute patched_path =~ "time_axis="
    refute patched_path =~ "replay_run_id="
    refute patched_path =~ "limit_mode="

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"][data-dashboard-time-mode="live"][data-dashboard-data-realm="rehearsal"][data-dashboard-data-view="canonical"][data-dashboard-source-binding-id="#{rehearsal_source.binding_id}"][data-dashboard-limit-mode="observed"][data-engine-time-mode="live"][data-engine-data-realm="rehearsal"][data-engine-data-view="canonical"][data-engine-source-binding-id="#{rehearsal_source.binding_id}"][data-engine-limit-mode="observed"])
           )
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
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
      Cadence.Persistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
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

  defp replace_dashboard_row_document!(org, mission, %Document{} = document) do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{document: JsonDocument.encode(Document.to_map(document))})
    |> Repo.update!()

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
end
