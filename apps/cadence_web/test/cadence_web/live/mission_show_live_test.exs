defmodule CadenceWeb.MissionShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderProfile}
  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  defp persist_mission!(org, slug, display_name) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.Missions.persist_mission(mission)
    persisted
  end

  defp persist_ready_spacecraft_comms_setup!(org, mission) do
    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)

    assert {:ok, endpoint} =
             Cadence.SourceEndpoints.ensure_managed_source_endpoint(
               org.organization_id,
               spacecraft
             )

    provider =
      ProviderProfile.new(%{
        mission_id: mission.mission_id,
        adapter_key: :tcp_socket,
        metadata: %{"display_name" => "TCP Provider"}
      })

    assert {:ok, provider} =
             Cadence.Contacts.persist_provider_profile(org.organization_id, provider)

    path_template =
      PathTemplate.new(%{
        mission_id: mission.mission_id,
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: endpoint.source_endpoint_id,
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ],
        metadata: %{"display_name" => "Alpha downlink"}
      })

    assert {:ok, path_template} =
             Cadence.Contacts.persist_path_template(org.organization_id, path_template)

    link_assignment =
      LinkAssignment.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: endpoint.source_endpoint_id,
        path_template_id: path_template.path_template_id,
        path_template_version: path_template.version,
        direction: path_template.direction,
        selection_role: path_template.selection_role,
        provider_profile_refs: path_template.provider_profile_refs,
        metadata: %{"display_name" => "Alpha downlink"}
      })

    assert {:ok, _link_assignment} =
             Cadence.Contacts.persist_link_assignment(org.organization_id, link_assignment)

    %{
      spacecraft: spacecraft,
      endpoint: endpoint,
      provider: provider,
      path_template: path_template
    }
  end

  defp mission_overview(view) do
    vue = LiveVue.Test.get_vue(view, id: "mission-overview-component")
    assert vue.component == "MissionOverview"
    assert vue.class == "space-y-6"
    {vue.props["overview"], spacecraft_readiness_rows(vue)}
  end

  defp spacecraft_readiness_rows(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/spacecraft_readiness/" <> _index, _row] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end

  defp expected_readiness_cards(ready_count, missing_scid_count, missing_path_count) do
    [
      %{
        "title" => "Ready Spacecraft",
        "value" => ready_count,
        "status" =>
          if(ready_count == 0,
            do: %{"tone" => "attention", "label" => "Needs Work"},
            else: %{"tone" => "ready", "label" => "Ready"}
          ),
        "description" => "Spacecraft with SCID and identity configured."
      },
      %{
        "title" => "Need SCID",
        "value" => missing_scid_count,
        "status" =>
          if(missing_scid_count == 0,
            do: %{"tone" => "ready", "label" => "Ready"},
            else: %{"tone" => "blocked", "label" => "Missing"}
          ),
        "description" => "Spacecraft that cannot be resolved from incoming frames yet."
      },
      %{
        "title" => "Need Link",
        "value" => missing_path_count,
        "status" =>
          if(missing_path_count == 0,
            do: %{"tone" => "ready", "label" => "Ready"},
            else: %{"tone" => "attention", "label" => "Needs Work"}
          ),
        "description" => "Spacecraft with identity configured but no provider link."
      }
    ]
  end

  defp expected_setup(mission_id, issue_count, empty?) do
    %{
      "eyebrow" => "Spacecraft Readiness",
      "title" => "Configure spacecraft identity and select a spacecraft profile",
      "description" =>
        "Each row shows whether a spacecraft can be identified from incoming frames and has a profile that defines its byte-interpretation contract.",
      "issue_count" => issue_count,
      "status" =>
        if(issue_count == 0,
          do: %{"tone" => "ready", "label" => "Ready"},
          else: %{"tone" => "attention", "label" => "Needs Work"}
        ),
      "empty" => empty?,
      "empty_state" => %{
        "title" => "No spacecraft have been registered for this mission yet.",
        "action_label" => "Add the first spacecraft",
        "action_href" => "/missions/#{mission_id}/spacecraft/new"
      }
    }
  end

  describe "mount" do
    test "renders mission heading with the mission sidebar layout" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "alpha", "Alpha Mission")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert has_element?(view, "#mission-overview-page")
      assert has_element?(view, "#mission-overview-component")

      {overview, []} = mission_overview(view)

      assert overview["mission"] == %{
               "eyebrow" => "Mission",
               "display_name" => "Alpha Mission",
               "slug" => "alpha"
             }

      sidebar = LiveVue.Test.get_vue(view, id: "mission-sidebar-navigation")
      presentation = sidebar.props["presentation"]
      overview_nav = hd(presentation["navigation"]["items"])

      assert overview_nav["attrs"]["href"] == "/missions/#{mission.mission_id}"
      assert overview_nav["label"] == "Overview"
      assert overview_nav["class"] =~ "border-primary"
      assert presentation["organization"]["link"]["attrs"]["href"] == "/"
      assert presentation["organization"]["link"]["label"] == "Cadence Ops"
    end

    test "renders the spacecraft readiness empty state and setup status" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "primary", "Primary Mission")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      {overview, rows} = mission_overview(view)

      assert overview["readiness_cards"] == expected_readiness_cards(0, 0, 0)
      assert overview["setup"] == expected_setup(mission.mission_id, 0, true)
      assert rows == []
    end

    test "shows spacecraft readiness from SCID and runtime state" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "primary", "Primary Mission")
      missing_scid = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")
      ready = persist_ready_spacecraft_comms_setup!(org, mission)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")
      {overview, rows} = mission_overview(view)

      assert overview["readiness_cards"] == expected_readiness_cards(1, 1, 0)
      assert overview["setup"] == expected_setup(mission.mission_id, 1, false)

      assert rows == [
               %{
                 "id" => missing_scid.spacecraft_id,
                 "__dom_id" => "spacecraft_readiness-#{missing_scid.spacecraft_id}",
                 "actions_id" => "#{missing_scid.spacecraft_id}-readiness-actions",
                 "spacecraft_display_name" => "Needs SCID",
                 "spacecraft_id" => missing_scid.spacecraft_id,
                 "scid_label" => "Not set",
                 "endpoint_label" => "Missing",
                 "endpoint_ref_label" => "Not created",
                 "path_label" => "No downlink route",
                 "path_detail" => "Not configured",
                 "status" => "blocked",
                 "status_label" => "Needs identity",
                 "issue" =>
                   "Set SCID so Cadence can identify this spacecraft from TM transfer frames.",
                 "primary_action" => "Set SCID",
                 "primary_action_href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{missing_scid.spacecraft_id}/readiness",
                 "view_spacecraft_href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{missing_scid.spacecraft_id}"
               },
               %{
                 "id" => ready.spacecraft.spacecraft_id,
                 "__dom_id" => "spacecraft_readiness-#{ready.spacecraft.spacecraft_id}",
                 "actions_id" => "#{ready.spacecraft.spacecraft_id}-readiness-actions",
                 "spacecraft_display_name" => "Alpha",
                 "spacecraft_id" => ready.spacecraft.spacecraft_id,
                 "scid_label" => "42",
                 "endpoint_label" => "Telemetry identity",
                 "endpoint_ref_label" => ready.endpoint.source_endpoint_id,
                 "path_label" => "1 downlink route",
                 "path_detail" => "1 provider-backed",
                 "status" => "ready",
                 "status_label" => "Ready",
                 "issue" => "Ready for spacecraft telemetry routing.",
                 "primary_action" => "Review readiness",
                 "primary_action_href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{ready.spacecraft.spacecraft_id}/readiness",
                 "view_spacecraft_href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{ready.spacecraft.spacecraft_id}"
               }
             ]
    end
  end

  describe "authorization" do
    test "redirects to /missions when mission id is unknown" do
      {conn, _org} = signed_in_conn()

      assert {:error, {:redirect, %{to: "/missions"}}} =
               live(conn, ~p"/missions/mission_unknown")
    end
  end
end
