defmodule CadenceWeb.OpsDashboardShowLive.TelemetryExploreLiveTest do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Runtime.Persistence, as: RuntimePersistence
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.Document
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

  test "telemetry explore route renders point context and matching samples" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    source_context =
      persist_dashboard_realm_source!(
        mission,
        :rehearsal,
        "explore-rehearsal-tsdb",
        "explore-rehearsal-binding"
      )

    configure_telemetry_storage_source!(
      :rehearsal,
      source_context.data_source_id,
      source_context.binding_id
    )

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

    assert [older_sample, _latest_sample] =
             TelemetryReads.sample_history(
               org.organization_id,
               mission.mission_id,
               "HK.counter",
               spacecraft_id: spacecraft.spacecraft_id,
               order: :asc
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Power",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?#{%{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id, sample_id: older_sample.sample_id, selected_time: DateTime.to_iso8601(older_sample.receipt_time), realm: "rehearsal", data_source_id: source_context.data_source_id, source_binding_id: source_context.binding_id, source_dashboard_id: dashboard.dashboard_id}}"
      )

    assert has_element?(view, "#ops-telemetry-explore-page")

    assert has_element?(
             view,
             ~s(#ops-telemetry-explore-page[data-explore-source-state="matched"][data-explore-selected-sample-state="matched"][data-explore-data-source="#{source_context.data_source_id}"][data-explore-source-binding="#{source_context.binding_id}"])
           )

    assert has_element?(view, ~s([data-explore-point-field="Point"]), "HK.counter")
    assert has_element?(view, ~s([data-explore-context="Spacecraft"]), spacecraft.spacecraft_id)

    assert has_element?(
             view,
             ~s(#telemetry-explore-sample-#{older_sample.sample_id}[data-explore-selected])
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-selected-sample-card[data-explore-selected-sample-card="#{older_sample.sample_id}"])
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Evidence"]),
             older_sample.evidence_id
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Packet"]),
             older_sample.packet_id
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Definition"]),
             "#{older_sample.packet_definition_id}@#{older_sample.packet_definition_version}"
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Validity"]),
             "canonical"
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-sample-#{older_sample.sample_id} [data-explore-sample-evidence="#{older_sample.evidence_id}"])
           )

    assert has_element?(
             view,
             ~s([data-explore-open-sample="#{older_sample.sample_id}"])
           )

    assert has_element?(view, ~s([data-explore-diagnostics="Requested"]), "100")
    assert has_element?(view, ~s([data-explore-diagnostics="Returned"]), "2")
    assert has_element?(view, ~s([data-explore-diagnostics="Physical exists"]), "true")
    assert has_element?(view, ~s([data-explore-source="State"]), "matched")
    assert has_element?(view, ~s([data-explore-source="Logical source"]), "telemetry")

    assert has_element?(
             view,
             ~s(#telemetry-explore-source-card[data-explore-source-state="matched"][data-explore-matched-data-source="#{source_context.data_source_id}"][data-explore-matched-source-binding="#{source_context.binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-copy-link[data-clipboard-text*="/ops/explore"][data-clipboard-text*="point_id=HK.counter"][data-clipboard-text*="sample_id=#{older_sample.sample_id}"][data-clipboard-text*="data_source_id=#{source_context.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_context.binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-investigation-summary[data-investigation-path*="point_id=HK.counter"][data-investigation-fingerprint])
           )

    assert has_element?(view, "#telemetry-explore-back-to-dashboard")

    view |> element("#telemetry-explore-clear-selected-sample") |> render_click()
    cleared_path = assert_patch(view)
    assert cleared_path =~ "point_id=HK.counter"
    assert cleared_path =~ "spacecraft_id=#{URI.encode_www_form(spacecraft.spacecraft_id)}"
    refute cleared_path =~ "sample_id="
    refute cleared_path =~ "selected_time="
    refute cleared_path =~ "source_dashboard_id="
    refute has_element?(view, "#telemetry-explore-selected-sample-card")

    from = "2023-11-14T22:14:45Z"
    to = "2023-11-14T22:15:00Z"

    view
    |> element("#telemetry-explore-filter-form")
    |> render_submit(%{
      "explore" => %{
        "point_id" => "HK.counter",
        "spacecraft_id" => spacecraft.spacecraft_id,
        "time_mode" => "archive",
        "from" => from,
        "to" => to,
        "order" => "asc",
        "limit" => "1",
        "realm" => "rehearsal",
        "logical_source" => "telemetry",
        "data_source_id" => source_context.data_source_id,
        "source_binding_id" => source_context.binding_id,
        "source_dashboard_id" => dashboard.dashboard_id,
        "sample_id" => older_sample.sample_id,
        "selected_time" => DateTime.to_iso8601(older_sample.receipt_time)
      }
    })

    patched_path = assert_patch(view)
    assert patched_path =~ "point_id=HK.counter"
    assert patched_path =~ "time_mode=archive"
    assert patched_path =~ "from=#{URI.encode_www_form(from)}"
    assert patched_path =~ "to=#{URI.encode_www_form(to)}"
    assert patched_path =~ "order=asc"
    assert patched_path =~ "limit=1"
    assert patched_path =~ "realm=rehearsal"
    assert patched_path =~ "data_source_id=#{source_context.data_source_id}"
    assert patched_path =~ "source_binding_id=#{source_context.binding_id}"
    refute patched_path =~ "logical_source=telemetry"

    assert has_element?(view, ~s([data-explore-source="Requested realm"]), "rehearsal")

    assert has_element?(
             view,
             ~s([data-explore-source="Requested source"]),
             source_context.data_source_id
           )

    assert has_element?(
             view,
             ~s([data-explore-source="Requested binding"]),
             source_context.binding_id
           )

    view
    |> element("#telemetry-explore-filter-form")
    |> render_submit(%{
      "explore" => %{
        "point_id" => "HK.counter",
        "spacecraft_id" => spacecraft.spacecraft_id,
        "time_mode" => "latest",
        "order" => "desc",
        "limit" => "100",
        "selection_view" => "all_revisions",
        "validity_state" => "conflict",
        "realm" => "rehearsal",
        "data_source_id" => source_context.data_source_id,
        "source_binding_id" => source_context.binding_id,
        "source_dashboard_id" => dashboard.dashboard_id,
        "sample_id" => older_sample.sample_id,
        "selected_time" => DateTime.to_iso8601(older_sample.receipt_time)
      }
    })

    filtered_path = assert_patch(view)
    assert filtered_path =~ "selection_view=all_revisions"
    assert filtered_path =~ "validity_state=conflict"
    assert filtered_path =~ "realm=rehearsal"
    assert filtered_path =~ "data_source_id=#{source_context.data_source_id}"
    assert filtered_path =~ "source_binding_id=#{source_context.binding_id}"
    refute filtered_path =~ "time_mode=latest"
    refute filtered_path =~ "order=desc"
    refute filtered_path =~ "limit=100"

    assert render(view) =~
             "Physical samples exist, but none matched the current selection view or validity filter."

    assert has_element?(view, ~s([data-explore-diagnostics="Returned"]), "0")
    assert has_element?(view, ~s([data-explore-diagnostics="Physical exists"]), "true")

    assert has_element?(
             view,
             ~s(#ops-telemetry-explore-page[data-explore-source-state="matched"][data-explore-selected-sample-state="missing"])
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-selected-sample-status[data-explore-selected-sample-state="missing"][data-explore-selected-sample-id="#{older_sample.sample_id}"])
           )
  end

  test "telemetry explore route marks stale source evidence targets as missing" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?#{%{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id, realm: "rehearsal", data_source_id: "retired-rehearsal-tsdb", source_binding_id: "retired-rehearsal-binding"}}"
      )

    assert has_element?(
             view,
             ~s(#ops-telemetry-explore-page[data-explore-source-state="missing"][data-explore-data-source="retired-rehearsal-tsdb"][data-explore-source-binding="retired-rehearsal-binding"][data-explore-selected-sample-state="none"])
           )

    assert has_element?(
             view,
             ~s(#telemetry-explore-source-card[data-explore-source-state="missing"][data-explore-data-source="retired-rehearsal-tsdb"][data-explore-source-binding="retired-rehearsal-binding"])
           )

    assert has_element?(view, ~s([data-explore-source="State"]), "missing")
    assert has_element?(view, ~s([data-explore-diagnostics="Returned"]), "0")
  end

  test "question-led Explore stages a dashboard candidate without writing until Save" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               org.organization_id,
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               []
             )

    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Investigation Board")

    {:ok, explore, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore")

    assert has_element?(explore, "#ops-context-rail")
    assert has_element?(explore, "#telemetry-explore-questions")

    explore
    |> element("#telemetry-explore-question-what_changed")
    |> render_click()

    preset_path = assert_patch(explore)
    assert preset_path =~ "question=what_changed"
    assert preset_path =~ "time_mode=last_1h"
    assert preset_path =~ "selection_view=all_revisions"

    assert has_element?(
             explore,
             ~s(#telemetry-explore-question-briefing[data-explore-question="what_changed"])
           )

    assert has_element?(explore, "#telemetry-explore-question-timeline")
    assert has_element?(explore, "#telemetry-explore-add-to-dashboard-form")

    explore
    |> form("#telemetry-explore-add-to-dashboard-form",
      add_to_dashboard: %{
        dashboard_id: dashboard.dashboard_id,
        widget_type: "time_series",
        title: "Counter investigation"
      }
    )
    |> render_submit()

    {editor_path, _flash} = assert_redirect(explore)
    assert editor_path =~ "/ops/dashboards/#{dashboard.dashboard_id}/edit"
    assert editor_path =~ "candidate_source=explore"
    assert editor_path =~ "candidate_point_id=HK.counter"

    assert version_count(org, mission, dashboard) == 1

    {:ok, editor, _html} = live(conn, editor_path)
    render_dashboard_async(editor)

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-dashboard-editor="true"][data-editor-dirty="true"])
           )

    assert version_count(org, mission, dashboard) == 1
    assert {:ok, %Document{placements: []}} = fetch_document(org, mission, dashboard)

    editor |> element("#dashboard-editor-save") |> render_click()
    render_dashboard_async(editor)

    assert version_count(org, mission, dashboard) == 2

    assert {:ok, %Document{placements: [placement]}} = fetch_document(org, mission, dashboard)
    assert placement.widget_def.title == "Counter investigation"
    assert placement.widget_def.binding.observables == ["HK.counter"]

    stop_dashboard_view(editor)
  end

  defp version_count(org, mission, dashboard) do
    Cadence.Dashboards.list_versions(
      org.organization_id,
      mission.mission_id,
      dashboard.dashboard_id
    )
    |> length()
  end

  defp fetch_document(org, mission, dashboard) do
    Cadence.Dashboards.fetch_document(
      org.organization_id,
      mission.mission_id,
      dashboard.dashboard_id
    )
  end
end
