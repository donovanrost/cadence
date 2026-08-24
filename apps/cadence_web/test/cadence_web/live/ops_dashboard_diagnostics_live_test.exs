defmodule CadenceWeb.OpsDashboardDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.RuntimeInvalidation
  alias CadenceWeb.TestFixtures

  test "diagnostic collections and master detail selection have stable URLs" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Diagnostics")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics?collection=cache"
      )

    assert has_element?(view, "#ops-dashboard-diagnostics-page-component.contents")
    refute has_element?(view, "#dashboard-diagnostics-page")

    vue = diagnostics_vue(view)

    assert vue.component == "OpsDashboardDiagnostics"
    assert vue.class == "contents"
    assert vue.use_diff == false
    refute vue.ssr
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert Enum.all?(vue.streams_diff, &diagnostic_stream_mutation?/1)

    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))

    presentation = vue.props["presentation"]
    cache_tab = collection_presentation(presentation, "cache")
    assert cache_tab["attrs"]["class"] =~ "text-primary"

    [cache_row] = diagnostic_stream_rows(vue)
    assert cache_row["__dom_id"] == "dashboard-diagnostic-row-cache-contract"

    copy = presentation["detail"]["selected"]["header"]["copy"]

    assert copy["component"] == "ClipboardButton"
    assert copy["props"]["button_id"] == "dashboard-diagnostic-copy-identity"
    assert copy["props"]["clipboard_text"] == "#{dashboard.dashboard_id}:cache"
    assert copy["props"]["button_class"] == "btn btn-outline btn-xs"
    assert copy["props"]["icon"] == "hero-clipboard"
    assert copy["props"]["icon_class"] == "h-3.5 w-3.5"
    assert copy["props"]["label"] == "Copy identity"
    assert copy["host"]["attrs"]["class"] == "contents"
    refute vue.ssr

    drilldowns = presentation["detail"]["selected"]["drilldowns"]["links"]
    assert Enum.any?(drilldowns, &(&1["attrs"]["id"] == "diagnostics-open-explore"))
    assert Enum.any?(drilldowns, &(&1["attrs"]["id"] == "diagnostics-open-sources"))
    assert Enum.any?(drilldowns, &(&1["attrs"]["id"] == "diagnostics-open-catalog"))

    invalidations_tab = collection_presentation(presentation, "invalidations")
    assert invalidations_tab["attrs"]["data-phx-link"] == "patch"
    render_patch(view, invalidations_tab["attrs"]["href"])

    assert_patch(
      view,
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics?collection=invalidations"
    )

    patched_presentation = diagnostics_vue(view).props["presentation"]
    assert patched_presentation["master"]["header"]["count"]["text"] == "0"
  end

  test "durable invalidation decisions expose context, impact, and refresh evidence" do
    {conn, _user, organization, mission} = signed_in_user_org_and_mission()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Invalidation Diagnostics",
        widgets: [%{type: :value_tile, title: "Counter", binding: %{point_id: "HK.counter"}}]
      )

    occurred_at = ~U[2026-08-01 12:00:00Z]

    invalidation =
      RuntimeInvalidation.Event.new(
        :historical_data_changed,
        [:source_result, :frame],
        %{
          organization_id: organization.organization_id,
          mission_id: mission.mission_id,
          logical_source: :telemetry,
          observable: "HK.counter",
          replay_run_id: "replay-run-1"
        },
        %{},
        %{plans: 0, source_results: 1, frames: 1, total: 2},
        occurred_at: occurred_at
      )

    assert {:ok, decision} =
             Cadence.record_dashboard_runtime_invalidation_decision(
               invalidation,
               %{
                 dashboard_id: dashboard.dashboard_id,
                 organization_id: organization.organization_id,
                 mission_id: mission.mission_id,
                 affected_placement_count: 1,
                 affected_placement_ids: [List.first(dashboard.placements).placement_id],
                 affected_widget_type_ids: ["cadence.value_tile"],
                 affected_impact_reasons: [:primary_source],
                 matches?: false,
                 dashboard_matches?: true,
                 context_matches?: false,
                 context_reason: :replay_run_mismatch,
                 refresh_allowed?: false,
                 refresh_reason: :stale_for_context,
                 decision_status: :filtered
               },
               decision_observed_at: ~U[2026-08-01 12:00:05Z]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics?collection=invalidations"
      )

    vue = diagnostics_vue(view)
    presentation = vue.props["presentation"]
    assert presentation["master"]["header"]["count"]["text"] == "1"

    row =
      Enum.find(
        diagnostic_stream_rows(vue),
        &String.contains?(&1["attrs"]["data-diagnostic-id"], decision.invalidation_event_id)
      )

    assert row
    assert row["status"]["text"] == "filtered"
    assert row["title"]["text"] =~ "historical_data_changed"

    details = presentation["detail"]["selected"]["details"]["items"]

    assert Enum.any?(details, &String.contains?(&1["value"]["text"], "replay_run_mismatch"))
    assert Enum.any?(details, &String.contains?(&1["value"]["text"], "stale_for_context"))

    copy = presentation["detail"]["selected"]["header"]["copy"]

    assert copy["component"] == "ClipboardButton"
    assert copy["props"]["button_id"] == "dashboard-diagnostic-copy-identity"
    assert copy["props"]["clipboard_text"] =~ decision.invalidation_event_id
    refute vue.ssr
  end

  test "diagnostic presentation attrs preserve HEEx coercion semantics" do
    assert CadenceWeb.OpsDashboardDiagnosticsLive.presentation_attrs(%{
             "nil" => nil,
             "false" => false,
             "true" => true,
             "string-false" => "false",
             "empty" => "",
             "number" => 7
           }) == %{
             "true" => "",
             "string-false" => "false",
             "empty" => "",
             "number" => "7"
           }
  end

  defp diagnostics_vue(view_or_html) do
    LiveVue.Test.get_vue(view_or_html, id: "ops-dashboard-diagnostics-page-component")
  end

  defp collection_presentation(presentation, collection) do
    Enum.find(presentation["collections"]["items"], &(&1["key"] == collection))
  end

  defp diagnostic_stream_rows(vue) do
    for ["upsert", path, row] <- vue.streams_diff,
        String.starts_with?(path, "/diagnostic_rows/"),
        do: row
  end

  defp diagnostic_stream_mutation?(["replace", "/diagnostic_rows", []]), do: true

  defp diagnostic_stream_mutation?(["upsert", path, _row]),
    do: String.starts_with?(path, "/diagnostic_rows/")

  defp diagnostic_stream_mutation?(_mutation), do: false

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-diagnostics")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
