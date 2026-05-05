defmodule CadenceWeb.CommsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderProfile, TransportProfile}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp persist_complete_comms_setup!(org, mission) do
    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)

    endpoint =
      SourceEndpoint.new(%{
        mission_id: mission.mission_id,
        display_name: "Alpha endpoint",
        source_ref: "alpha",
        scid: 42
      })

    assert {:ok, endpoint} = Cadence.persist_source_endpoint(org.organization_id, endpoint)

    provider =
      ProviderProfile.new(%{
        mission_id: mission.mission_id,
        adapter_key: :tcp_socket,
        metadata: %{"display_name" => "TCP Provider"}
      })

    assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

    transport =
      TransportProfile.new(%{
        mission_id: mission.mission_id,
        family_key: :heartbeat_monitor,
        target_scope: :path,
        metadata: %{"display_name" => "Heartbeat Monitor"}
      })

    assert {:ok, transport} = Cadence.persist_transport_profile(org.organization_id, transport)

    path_template =
      PathTemplate.new(%{
        mission_id: mission.mission_id,
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: endpoint.source_endpoint_id,
        provider_path_ref: "gs-a-downlink",
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ],
        transport_profile_refs: [
          %{
            "transport_profile_id" => transport.transport_profile_id,
            "version" => transport.version
          }
        ],
        metadata: %{"display_name" => "Alpha downlink"}
      })

    assert {:ok, path_template} =
             Cadence.persist_path_template(org.organization_id, path_template)

    link_assignment =
      LinkAssignment.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: endpoint.source_endpoint_id,
        path_template_id: path_template.path_template_id,
        path_template_version: path_template.version,
        direction: path_template.direction,
        selection_role: path_template.selection_role,
        provider_path_ref: "gs-a-downlink",
        provider_profile_refs: path_template.provider_profile_refs,
        transport_profile_refs: path_template.transport_profile_refs,
        metadata: %{"display_name" => "Alpha downlink"}
      })

    assert {:ok, _link_assignment} =
             Cadence.persist_link_assignment(org.organization_id, link_assignment)

    %{endpoint: endpoint, provider: provider, transport: transport, path_template: path_template}
  end

  defp persist_ready_spacecraft_comms_setup!(org, mission) do
    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)

    assert {:ok, endpoint} =
             Cadence.ensure_managed_spacecraft_source_endpoint(org.organization_id, spacecraft)

    provider =
      ProviderProfile.new(%{
        mission_id: mission.mission_id,
        adapter_key: :tcp_socket,
        metadata: %{"display_name" => "TCP Provider"}
      })

    assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

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
             Cadence.persist_path_template(org.organization_id, path_template)

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
             Cadence.persist_link_assignment(org.organization_id, link_assignment)

    %{
      spacecraft: spacecraft,
      endpoint: endpoint,
      provider: provider,
      path_template: path_template
    }
  end

  describe "overview" do
    test "renders the comms setup overview and section navigation" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-overview-page")
      assert has_element?(view, "#comms-section-nav")
      assert has_element?(view, "#comms-nav-links")
      assert has_element?(view, "#comms-nav-path-templates")
      assert has_element?(view, "#spacecraft-readiness-table")
      assert has_element?(view, "#configure-missing-links")
      assert has_element?(view, "#mission-network-resources")
      assert has_element?(view, "#mission-network-links")
      assert has_element?(view, "#mission-network-protocol-behaviors")
      assert has_element?(view, "#mission-network-link-templates")
      assert has_element?(view, "#mission-network-validation")
      assert has_element?(view, "#mission-network-advanced")
      assert render(view) =~ "Mission Network"
      assert render(view) =~ "Shared mission connectivity"
      assert render(view) =~ "Spacecraft Readiness"
    end

    test "shows spacecraft readiness from SCID, runtime identity, and link state" do
      {conn, org, mission} = signed_in_org_and_mission()
      missing_scid = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")
      ready = persist_ready_spacecraft_comms_setup!(org, mission)

      needs_assignment =
        TestFixtures.persist_spacecraft!(mission, display_name: "Needs Assignment", scid: 84)

      assert {:ok, _endpoint} =
               Cadence.ensure_managed_spacecraft_source_endpoint(
                 org.organization_id,
                 needs_assignment
               )

      available_path =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => ready.provider.provider_profile_id,
              "version" => ready.provider.version
            }
          ],
          metadata: %{"display_name" => "Assignable downlink"}
        })

      assert {:ok, _available_path} =
               Cadence.persist_path_template(org.organization_id, available_path)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")
      html = render(view)

      assert html =~ missing_scid.display_name
      assert html =~ "Set SCID"
      assert html =~ "Needs identity"

      assert html =~ ready.spacecraft.display_name
      assert html =~ "Managed identity"
      assert html =~ "Ready for SCID-based telemetry routing."
      assert html =~ "Ready"

      assert html =~ needs_assignment.display_name
      assert html =~ "Available to assign"
      assert html =~ "2 available mission templates"
      assert html =~ "Assign an available downlink link template to this spacecraft."

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{ready.spacecraft.spacecraft_id}/readiness"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{ready.spacecraft.spacecraft_id}/links"

      assert html =~ "Link assignments"
    end

    test "overview validation count includes spacecraft interpretation findings" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(
               view,
               "#mission-network-validation",
               "Mission network, assignment, and interpretation findings."
             )

      assert has_element?(view, "#mission-network-validation span", "6")
    end

    test "expands the Comms section and marks Overview active on /comms" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      # The <details> for the Comms section is rendered open.
      assert has_element?(view, "details[open] summary", "Comms")

      # The Overview child link is present and styled active (text-primary on
      # the link itself; the active dot in its leading slot is bg-primary).
      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"].text-primary|,
               "Overview"
             )

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"] span.bg-primary|
             )
    end

    test "leaves the Comms section collapsed when not on a /comms route" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      # The Comms <summary> is rendered inside a <details> WITHOUT open.
      assert has_element?(view, "details:not([open]) summary", "Comms")
      refute has_element?(view, "details[open] summary", "Comms")
    end

    test "applies link templates to missing spacecraft links" do
      {conn, org, mission} = signed_in_org_and_mission()
      alpha = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 77)
      _missing_scid = TestFixtures.persist_spacecraft!(mission, display_name: "No SCID")
      ready = persist_ready_spacecraft_comms_setup!(org, mission)

      transport =
        TransportProfile.new(%{
          mission_id: mission.mission_id,
          family_key: :heartbeat_monitor,
          target_scope: :path,
          configuration: %{"heartbeat_interval_ms" => 1000},
          metadata: %{"display_name" => "Heartbeat Monitor"}
        })

      assert {:ok, transport} = Cadence.persist_transport_profile(org.organization_id, transport)

      source_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => ready.provider.provider_profile_id,
              "version" => ready.provider.version
            }
          ],
          transport_profile_refs: [
            %{
              "transport_profile_id" => transport.transport_profile_id,
              "version" => transport.version
            }
          ],
          metadata: %{"display_name" => "Shared downlink template"}
        })

      assert {:ok, source_template} =
               Cadence.persist_path_template(org.organization_id, source_template)

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/apply-link-template")

      assert has_element?(view, "#comms-apply-link-template-page")

      assert has_element?(
               view,
               "#link-application-form select[name='link_application[path_template_id]']"
             )

      assert html =~ "Ready to Apply"
      assert html =~ "Already Assigned"
      assert html =~ "Constellation link assignment plan"
      assert html =~ "Shared downlink template"
      assert html =~ "Alpha"
      assert html =~ "No SCID"
      assert html =~ ready.spacecraft.display_name

      assert has_element?(view, "#link-application-ready-count")
      assert has_element?(view, "#link-application-missing-scid-count")
      assert has_element?(view, "#link-application-existing-count")

      result_html =
        view
        |> form("#link-application-form",
          link_application: %{
            path_template_id: source_template.path_template_id,
            provider_path_ref_pattern: "gsa-{spacecraft_id}-{direction}",
            display_name_pattern: "{spacecraft_name} assigned {direction}",
            spacecraft_query: ""
          }
        )
        |> render_submit()

      assert result_html =~ "Application Result"
      assert has_element?(view, "#link-application-applied-count")
      assert has_element?(view, "#link-application-skipped-count")
      assert has_element?(view, "#link-application-failed-count")
      assert result_html =~ "Applied"
      assert result_html =~ "Skipped"

      assert {:ok, endpoint} =
               Cadence.fetch_source_endpoint(
                 org.organization_id,
                 mission.mission_id,
                 "spacecraft_runtime:" <> alpha.spacecraft_id
               )

      assert endpoint.scid == 77

      created =
        org.organization_id
        |> Cadence.list_link_assignments(mission.mission_id)
        |> Enum.find(&(&1.source_endpoint_ref == endpoint.source_endpoint_id))

      assert created.metadata["display_name"] == "Alpha assigned downlink"
      assert created.metadata["applied_from_template_ui"] == true
      assert created.metadata["source_path_template_id"] == source_template.path_template_id
      assert created.metadata["source_path_template_version"] == source_template.version
      assert created.provider_path_ref == "gsa-#{alpha.spacecraft_id}-downlink"

      assert created.provider_profile_refs == [
               %{"provider_profile_id" => ready.provider.provider_profile_id, "version" => 1}
             ]

      assert created.transport_profile_refs == [
               %{"transport_profile_id" => transport.transport_profile_id, "version" => 1}
             ]
    end

    test "creates a shared mission link from one workflow" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/links/new")

      assert has_element?(view, "#comms-link-builder-page")
      assert html =~ "New Shared Mission Link"
      assert html =~ "Provider"
      assert html =~ "Protocol Behavior"

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#mission-link-builder-form",
                 mission_link: %{
                   display_name: "Goldstone TCP",
                   direction: "bidirectional",
                   selection_role: "candidate",
                   provider_path_ref: "",
                   tcp_mode: "connect",
                   host: "10.0.0.15",
                   port: "4555",
                   framing_mode: "fixed_size",
                   frame_size: "1024",
                   tls_enabled: "true",
                   heartbeat_enabled: "true",
                   heartbeat_interval_ms: "2500"
                 }
               )
               |> render_submit()

      assert target == ~p"/missions/#{mission.mission_id}/comms/link-templates"

      [provider] = Cadence.list_provider_profiles(org.organization_id, mission.mission_id)
      assert provider.metadata["display_name"] == "Goldstone TCP Provider"
      assert provider.configuration["mode"] == "connect"
      assert provider.configuration["direction"] == "bidirectional"
      assert provider.configuration["host"] == "10.0.0.15"
      assert provider.configuration["port"] == 4555
      assert provider.configuration["fixed_message_bytes"] == 1024
      assert provider.configuration["tls"] == %{"enabled" => true}

      [transport] = Cadence.list_transport_profiles(org.organization_id, mission.mission_id)
      assert transport.metadata["display_name"] == "Goldstone TCP Heartbeat"
      assert transport.configuration["heartbeat_interval_ms"] == 2500

      path_templates = Cadence.list_path_templates(org.organization_id, mission.mission_id)
      assert Enum.map(path_templates, & &1.direction) |> Enum.sort() == [:downlink, :uplink]
      assert Enum.all?(path_templates, &(&1.selection_role == :candidate))
      assert Enum.all?(path_templates, &is_nil(&1.source_endpoint_ref))
      assert Enum.all?(path_templates, &(&1.metadata["created_from_link_builder"] == true))

      assert Enum.map(path_templates, & &1.provider_profile_refs) == [
               [%{"provider_profile_id" => provider.provider_profile_id, "version" => 1}],
               [%{"provider_profile_id" => provider.provider_profile_id, "version" => 1}]
             ]

      assert Enum.map(path_templates, & &1.transport_profile_refs) == [
               [%{"transport_profile_id" => transport.transport_profile_id, "version" => 1}],
               [%{"transport_profile_id" => transport.transport_profile_id, "version" => 1}]
             ]
    end

    test "applies link templates only to spacecraft matching the filter" do
      {conn, org, mission} = signed_in_org_and_mission()
      target = TestFixtures.persist_spacecraft!(mission, display_name: "Target Sat", scid: 77)
      other = TestFixtures.persist_spacecraft!(mission, display_name: "Other Sat", scid: 88)

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "Mission TCP"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      source_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Shared downlink"}
        })

      assert {:ok, source_template} =
               Cadence.persist_path_template(org.organization_id, source_template)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/apply-link-template")

      result_html =
        view
        |> form("#link-application-form",
          link_application: %{
            path_template_id: source_template.path_template_id,
            provider_path_ref_pattern: "filtered-{spacecraft_id}",
            display_name_pattern: "{spacecraft_name} filtered",
            spacecraft_query: "Target"
          }
        )
        |> render_submit()

      assert result_html =~ "Target Sat"
      refute result_html =~ "Other Sat"

      source_endpoints = Cadence.list_source_endpoints(org.organization_id, mission.mission_id)

      assert Enum.any?(
               source_endpoints,
               &(&1.source_endpoint_id == "spacecraft_runtime:" <> target.spacecraft_id)
             )

      refute Enum.any?(
               source_endpoints,
               &(&1.source_endpoint_id == "spacecraft_runtime:" <> other.spacecraft_id)
             )

      assigned_link =
        org.organization_id
        |> Cadence.list_link_assignments(mission.mission_id)
        |> Enum.find(&(&1.provider_path_ref == "filtered-#{target.spacecraft_id}"))

      assert assigned_link.metadata["display_name"] == "Target Sat filtered"
    end

    test "applies link templates only to explicitly selected spacecraft" do
      {conn, org, mission} = signed_in_org_and_mission()
      target = TestFixtures.persist_spacecraft!(mission, display_name: "Selected Sat", scid: 77)
      other = TestFixtures.persist_spacecraft!(mission, display_name: "Unselected Sat", scid: 88)

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "Mission TCP"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      source_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Shared downlink"}
        })

      assert {:ok, source_template} =
               Cadence.persist_path_template(org.organization_id, source_template)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/apply-link-template")

      view
      |> element("#select-link-application-#{target.spacecraft_id}")
      |> render_click()

      result_html =
        view
        |> form("#link-application-form",
          link_application: %{
            path_template_id: source_template.path_template_id,
            target_mode: "selected",
            provider_path_ref_pattern: "selected-{spacecraft_id}",
            display_name_pattern: "{spacecraft_name} selected",
            spacecraft_query: ""
          }
        )
        |> render_submit()

      assert result_html =~ "Selected Sat"
      refute result_html =~ "Unselected Sat"

      link_assignments = Cadence.list_link_assignments(org.organization_id, mission.mission_id)
      assert Enum.any?(link_assignments, &(&1.spacecraft_id == target.spacecraft_id))
      refute Enum.any?(link_assignments, &(&1.spacecraft_id == other.spacecraft_id))
    end

    test "reports provider path ref conflicts when applying a link template" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Target Sat", scid: 77)

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "Mission TCP"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      source_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Shared downlink"}
        })

      collision =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :candidate,
          provider_path_ref: "duplicate-provider-path",
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Existing provider path"}
        })

      assert {:ok, source_template} =
               Cadence.persist_path_template(org.organization_id, source_template)

      assert {:ok, _collision} = Cadence.persist_path_template(org.organization_id, collision)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/apply-link-template")

      result_html =
        view
        |> form("#link-application-form",
          link_application: %{
            path_template_id: source_template.path_template_id,
            provider_path_ref_pattern: "duplicate-provider-path",
            display_name_pattern: "{spacecraft_name} duplicate",
            spacecraft_query: "Target"
          }
        )
        |> render_submit()

      assert result_html =~ "Conflict"
      assert result_html =~ "Provider path ref duplicate-provider-path is already used"

      refute Enum.any?(
               Cadence.list_source_endpoints(org.organization_id, mission.mission_id),
               &(&1.source_endpoint_id == "spacecraft_runtime:" <> spacecraft.spacecraft_id)
             )
    end
  end

  describe "configuration pages" do
    test "lists runtime identities, providers, protocol behaviors, and link templates" do
      {conn, org, mission} = signed_in_org_and_mission()
      setup = persist_complete_comms_setup!(org, mission)

      {:ok, source_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/advanced/runtime-identities")

      assert has_element?(source_view, "#source-endpoints-table")
      assert render(source_view) =~ "Alpha endpoint"

      {:ok, provider_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

      assert has_element?(provider_view, "#provider-profiles-table")
      assert render(provider_view) =~ "TCP Provider"

      assert has_element?(
               provider_view,
               "a[href='/missions/#{mission.mission_id}/comms/providers/#{setup.provider.provider_profile_id}']"
             )

      {:ok, transport_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors")

      assert has_element?(transport_view, "#transport-profiles-table")
      assert render(transport_view) =~ "Heartbeat Monitor"

      assert has_element?(
               transport_view,
               "a[href='/missions/#{mission.mission_id}/comms/protocol-behaviors/#{setup.transport.transport_profile_id}']"
             )

      {:ok, path_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/link-templates")

      assert has_element?(path_view, "#path-templates-table")
      assert render(path_view) =~ "Alpha downlink"
      assert render(path_view) =~ "TCP Provider v1"
      assert render(path_view) =~ "Heartbeat Monitor v1"

      assert has_element?(
               path_view,
               "a[href='/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}']"
             )
    end

    test "shows validation findings for incomplete setup and clears them for complete setup" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, incomplete_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(incomplete_view, "#comms-validation-findings")
      assert has_element?(incomplete_view, "#comms-validation-mission-network")
      assert has_element?(incomplete_view, "#comms-validation-link-assignment")
      assert render(incomplete_view) =~ "No runtime identities configured"
      assert render(incomplete_view) =~ "Mission Network"
      assert render(incomplete_view) =~ "Link Assignments"

      _setup = persist_complete_comms_setup!(org, mission)

      {:ok, complete_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      complete_html = render(complete_view)

      assert has_element?(complete_view, "#comms-validation-page")
      assert has_element?(complete_view, "#comms-validation-findings")
      refute complete_html =~ "No providers configured"
      refute complete_html =~ "No runtime identities configured"
      refute complete_html =~ "needs a downlink assignment"
      assert complete_html =~ "Alpha telemetry interpretation is not configured"
    end

    test "groups spacecraft interpretation validation findings" do
      {conn, _org, mission} = signed_in_org_and_mission()
      missing_identity = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      needs_telemetry =
        TestFixtures.persist_spacecraft!(mission, display_name: "Needs Telemetry", scid: 42)

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(view, "#comms-validation-spacecraft-interpretation")
      assert html =~ "Spacecraft Interpretation"
      assert html =~ "Needs SCID is missing SCID"
      assert html =~ "Needs SCID telemetry interpretation is not configured"
      assert html =~ "Needs Telemetry telemetry interpretation is not configured"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{missing_identity.spacecraft_id}/identity"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{needs_telemetry.spacecraft_id}/telemetry"
    end

    test "groups link assignment validation findings for spacecraft downlinks" do
      {conn, org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "Needs Assignment", scid: 42)

      assert {:ok, _endpoint} =
               Cadence.ensure_managed_spacecraft_source_endpoint(org.organization_id, spacecraft)

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "TCP Provider"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      available_downlink =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Shared downlink"}
        })

      assert {:ok, _available_downlink} =
               Cadence.persist_path_template(org.organization_id, available_downlink)

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(view, "#comms-validation-link-assignment")
      assert html =~ "Needs Assignment needs a downlink assignment"
      assert html =~ "Assign an available provider-backed mission downlink"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
    end

    test "scopes selected uplink validation by runtime identity" do
      mission_id = "mission-validation"

      endpoint_a =
        SourceEndpoint.new(%{
          source_endpoint_id: "runtime-alpha",
          mission_id: mission_id,
          display_name: "Runtime Alpha"
        })

      endpoint_b =
        SourceEndpoint.new(%{
          source_endpoint_id: "runtime-beta",
          mission_id: mission_id,
          display_name: "Runtime Beta"
        })

      provider =
        ProviderProfile.new(%{
          provider_profile_id: "provider-alpha",
          mission_id: mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "TCP Provider"}
        })

      alpha_uplink =
        LinkAssignment.new(%{
          link_assignment_id: "alpha-uplink",
          mission_id: mission_id,
          spacecraft_id: "spacecraft-alpha",
          direction: :uplink,
          selection_role: :selected,
          source_endpoint_ref: endpoint_a.source_endpoint_id,
          path_template_id: "uplink-template-alpha",
          path_template_version: 1,
          provider_profile_refs: [%{"provider_profile_id" => provider.provider_profile_id}]
        })

      beta_uplink =
        LinkAssignment.new(%{
          link_assignment_id: "beta-uplink",
          mission_id: mission_id,
          spacecraft_id: "spacecraft-beta",
          direction: :uplink,
          selection_role: :selected,
          source_endpoint_ref: endpoint_b.source_endpoint_id,
          path_template_id: "uplink-template-beta",
          path_template_version: 1,
          provider_profile_refs: [%{"provider_profile_id" => provider.provider_profile_id}]
        })

      findings =
        CadenceWeb.CommsValidationLive.findings(
          [endpoint_a, endpoint_b],
          [],
          [provider],
          [],
          mission_id,
          [alpha_uplink, beta_uplink]
        )

      refute Enum.any?(findings, &String.starts_with?(&1.title, "Multiple selected uplink"))

      duplicate_alpha_uplink =
        LinkAssignment.new(%{
          link_assignment_id: "duplicate-alpha-uplink",
          mission_id: mission_id,
          spacecraft_id: "spacecraft-alpha",
          direction: :uplink,
          selection_role: :selected,
          source_endpoint_ref: endpoint_a.source_endpoint_id,
          path_template_id: "uplink-template-alpha-duplicate",
          path_template_version: 1,
          provider_profile_refs: [%{"provider_profile_id" => provider.provider_profile_id}]
        })

      findings =
        CadenceWeb.CommsValidationLive.findings(
          [endpoint_a, endpoint_b],
          [],
          [provider],
          [],
          mission_id,
          [alpha_uplink, duplicate_alpha_uplink]
        )

      assert Enum.any?(
               findings,
               &(&1.title == "Multiple selected uplink link templates for Runtime Alpha")
             )
    end

    test "flags link templates pinned to stale profile versions" do
      {conn, org, mission} = signed_in_org_and_mission()
      setup = persist_complete_comms_setup!(org, mission)

      assert {:ok, _provider_v2} =
               Cadence.version_provider_profile(
                 org.organization_id,
                 mission.mission_id,
                 setup.provider.provider_profile_id,
                 %{
                   configuration: %{"host" => "127.0.0.1", "port" => 5100},
                   metadata: %{"display_name" => "TCP Provider"}
                 }
               )

      assert {:ok, _transport_v2} =
               Cadence.version_transport_profile(
                 org.organization_id,
                 mission.mission_id,
                 setup.transport.transport_profile_id,
                 %{
                   configuration: %{"heartbeat_interval_ms" => 2000},
                   metadata: %{"display_name" => "Heartbeat Monitor"}
                 }
               )

      {:ok, validation_view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(validation_view, "#comms-validation-mission-network")
      assert html =~ "Alpha downlink uses TCP Provider v1; latest is v2."
      assert html =~ "Alpha downlink uses Heartbeat Monitor v1; latest is v2."

      assert has_element?(
               validation_view,
               "a[href='/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}/new-version']",
               "Create new link template version"
             )

      {:ok, show_view, show_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}"
        )

      assert has_element?(show_view, "#path-template-profile-version-findings")
      assert show_html =~ "Profile Version Drift"
      assert show_html =~ "Alpha downlink uses TCP Provider v1; latest is v2."
      assert show_html =~ "Alpha downlink uses Heartbeat Monitor v1; latest is v2."

      {:ok, version_view, version_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}/new-version"
        )

      assert has_element?(version_view, "#path-template-version-upgrade-preview")
      assert version_html =~ "TCP Provider will update from v1 to v2."
      assert version_html =~ "Heartbeat Monitor will update from v1 to v2."
      assert version_html =~ "TCP Provider · current v1 -&gt; latest v2"
      assert version_html =~ "Heartbeat Monitor · current v1 -&gt; latest v2"

      assert {:error, {:live_redirect, %{to: target}}} =
               version_view
               |> form("#path-template-form",
                 path_template: %{
                   display_name: "Alpha downlink",
                   direction: "downlink",
                   selection_role: "selected",
                   provider_path_ref: "gs-a-downlink",
                   provider_profile_id: setup.provider.provider_profile_id,
                   transport_profile_id: setup.transport.transport_profile_id
                 }
               )
               |> render_submit()

      assert target ==
               ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}"

      [latest_path, _original_path] =
        Cadence.list_path_template_versions(
          org.organization_id,
          mission.mission_id,
          setup.path_template.path_template_id
        )

      assert latest_path.provider_profile_refs == [
               %{"provider_profile_id" => setup.provider.provider_profile_id, "version" => 2}
             ]

      assert latest_path.transport_profile_refs == [
               %{"transport_profile_id" => setup.transport.transport_profile_id, "version" => 2}
             ]

      {:ok, upgraded_show_view, upgraded_show_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}"
        )

      refute has_element?(upgraded_show_view, "#path-template-profile-version-findings")
      refute upgraded_show_html =~ "Profile Version Drift"
    end

    test "flags link templates that reference archived profiles" do
      {conn, org, mission} = signed_in_org_and_mission()
      setup = persist_complete_comms_setup!(org, mission)

      assert {:ok, _archived_provider} =
               Cadence.delete_provider_profile(
                 org.organization_id,
                 mission.mission_id,
                 setup.provider.provider_profile_id
               )

      {:ok, validation_view, validation_html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(validation_view, "#comms-validation-findings")
      assert validation_html =~ "Alpha downlink references an archived provider"
      assert validation_html =~ "archived TCP Provider v1"

      {:ok, show_view, show_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}"
        )

      assert has_element?(show_view, "#path-template-profile-version-findings")
      assert show_html =~ "TCP Provider (archived)"

      {:ok, new_path_view, new_path_html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/link-templates/new")

      refute new_path_html =~ "TCP Provider"

      refute has_element?(
               new_path_view,
               "select[name='path_template[provider_profile_id]'] option[value='#{setup.provider.provider_profile_id}']"
             )
    end
  end

  describe "configuration creation" do
    test "creates runtime identities, providers, protocol behaviors, and link templates" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, source_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/advanced/runtime-identities/new")

      assert {:error, {:live_redirect, %{to: source_target}}} =
               source_view
               |> form("#source-endpoint-form",
                 source_endpoint: %{
                   display_name: "Alpha endpoint",
                   source_ref: "alpha",
                   scid: "42"
                 }
               )
               |> render_submit()

      assert source_target ==
               ~p"/missions/#{mission.mission_id}/comms/advanced/runtime-identities"

      [endpoint] = Cadence.list_source_endpoints(org.organization_id, mission.mission_id)
      assert endpoint.display_name == "Alpha endpoint"
      assert endpoint.scid == 42

      {:ok, provider_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

      assert {:error, {:live_redirect, %{to: provider_target}}} =
               provider_view
               |> form("#provider-profile-form",
                 provider_profile: %{
                   display_name: "TCP Provider",
                   tcp_mode: "listen",
                   direction: "downlink",
                   host: "127.0.0.1",
                   port: "5000",
                   framing_mode: "fixed_size",
                   frame_size: "10",
                   tls_enabled: "false"
                 }
               )
               |> render_submit()

      assert provider_target == ~p"/missions/#{mission.mission_id}/comms/providers"
      [provider] = Cadence.list_provider_profiles(org.organization_id, mission.mission_id)
      assert provider.metadata["display_name"] == "TCP Provider"
      assert provider.adapter_key == :tcp_socket
      assert provider.configuration["mode"] == "listen"
      assert provider.configuration["host"] == "127.0.0.1"
      assert provider.configuration["port"] == 5000
      assert provider.configuration["direction"] == "downlink"

      assert provider.configuration["framing"] == %{
               "mode" => "fixed_size",
               "fixed_message_bytes" => 10
             }

      assert provider.configuration["fixed_message_bytes"] == 10

      {:ok, transport_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/new")

      assert {:error, {:live_redirect, %{to: transport_target}}} =
               transport_view
               |> form("#transport-profile-form",
                 transport_profile: %{
                   display_name: "Heartbeat Monitor",
                   family_key: "heartbeat_monitor",
                   target_scope: "path",
                   heartbeat_interval_ms: "1000"
                 }
               )
               |> render_submit()

      assert transport_target == ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors"
      [transport] = Cadence.list_transport_profiles(org.organization_id, mission.mission_id)
      assert transport.metadata["display_name"] == "Heartbeat Monitor"
      assert transport.configuration["heartbeat_interval_ms"] == 1000

      {:ok, path_view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/link-templates/new")

      assert {:error, {:live_redirect, %{to: path_target}}} =
               path_view
               |> form("#path-template-form",
                 path_template: %{
                   display_name: "Alpha downlink",
                   direction: "downlink",
                   selection_role: "selected",
                   provider_path_ref: "gs-a-downlink",
                   provider_profile_id: provider.provider_profile_id,
                   transport_profile_id: transport.transport_profile_id
                 }
               )
               |> render_submit()

      assert path_target == ~p"/missions/#{mission.mission_id}/comms/link-templates"
      [path_template] = Cadence.list_path_templates(org.organization_id, mission.mission_id)
      assert path_template.metadata["display_name"] == "Alpha downlink"
      assert path_template.source_endpoint_ref == nil

      assert path_template.provider_profile_refs == [
               %{"provider_profile_id" => provider.provider_profile_id, "version" => 1}
             ]

      assert path_template.transport_profile_refs == [
               %{"transport_profile_id" => transport.transport_profile_id, "version" => 1}
             ]
    end

    test "creates an unassigned mission link template" do
      {conn, org, mission} = signed_in_org_and_mission()

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "Mission TCP"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/link-templates/new")

      assert html =~ "Network Path"
      refute html =~ "Assign To"

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#path-template-form",
                 path_template: %{
                   display_name: "Shared downlink",
                   direction: "downlink",
                   selection_role: "candidate",
                   provider_path_ref: "shared-downlink",
                   provider_profile_id: provider.provider_profile_id,
                   transport_profile_id: ""
                 }
               )
               |> render_submit()

      assert target == ~p"/missions/#{mission.mission_id}/comms/link-templates"

      [path_template] = Cadence.list_path_templates(org.organization_id, mission.mission_id)
      assert path_template.metadata["display_name"] == "Shared downlink"
      assert path_template.source_endpoint_ref == nil
      assert path_template.provider_path_ref == "shared-downlink"

      assert path_template.provider_profile_refs == [
               %{"provider_profile_id" => provider.provider_profile_id, "version" => 1}
             ]

      {:ok, list_view, list_html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/link-templates")

      assert has_element?(list_view, "#path-templates-table")
      assert list_html =~ "Shared downlink"
      assert list_html =~ "Reusable template"

      {:ok, _show_view, show_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{path_template.path_template_id}"
        )

      assert show_html =~ "Reusable mission template"
    end

    test "configuring a link for a spacecraft creates a reusable template without direct assignment" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 77)

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "Alpha TCP"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/new?spacecraft_id=#{spacecraft.spacecraft_id}"
        )

      assert has_element?(view, "#path-template-spacecraft-context")
      refute has_element?(view, "select[name='path_template[source_endpoint_ref]']")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#path-template-form",
                 path_template: %{
                   display_name: "Alpha downlink",
                   direction: "downlink",
                   selection_role: "selected",
                   provider_profile_id: provider.provider_profile_id
                 }
               )
               |> render_submit()

      assert target == ~p"/missions/#{mission.mission_id}/comms"

      [path_template] = Cadence.list_path_templates(org.organization_id, mission.mission_id)
      assert path_template.source_endpoint_ref == nil

      assert path_template.provider_profile_refs == [
               %{"provider_profile_id" => provider.provider_profile_id, "version" => 1}
             ]
    end

    test "shows and versions link templates" do
      {conn, org, mission} = signed_in_org_and_mission()
      setup = persist_complete_comms_setup!(org, mission)

      {:ok, show_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}"
        )

      assert has_element?(show_view, "#comms-path-template-show-page")
      assert html =~ "Alpha downlink"
      assert html =~ "Version History"
      assert html =~ "Coverage"
      assert html =~ "Assigned"
      assert html =~ "Alpha endpoint"
      assert html =~ "TCP Provider"

      {:ok, version_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}/new-version"
        )

      assert html =~ "New Link Template Version"

      assert render(version_view) =~ "gs-a-downlink"

      assert {:error, {:live_redirect, %{to: target}}} =
               version_view
               |> form("#path-template-form",
                 path_template: %{
                   display_name: "Alpha downlink updated",
                   direction: "downlink",
                   selection_role: "selected",
                   provider_path_ref: "gs-b-downlink",
                   provider_profile_id: setup.provider.provider_profile_id,
                   transport_profile_id: setup.transport.transport_profile_id
                 }
               )
               |> render_submit()

      assert target ==
               ~p"/missions/#{mission.mission_id}/comms/link-templates/#{setup.path_template.path_template_id}"

      [v2, v1] =
        Cadence.list_path_template_versions(
          org.organization_id,
          mission.mission_id,
          setup.path_template.path_template_id
        )

      assert v1.version == 1
      assert v2.version == 2
      assert v2.source_endpoint_ref == nil
      assert v2.provider_path_ref == "gs-b-downlink"
      assert v2.metadata["display_name"] == "Alpha downlink updated"
    end

    test "creates uplink gateway protocol behaviors" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/new")

      assert html =~ "Heartbeat Monitor"

      view
      |> form("#transport-profile-form",
        transport_profile: %{
          display_name: "TC Uplink Gateway",
          family_key: "uplink_gateway",
          target_scope: "path"
        }
      )
      |> render_change()

      assert {:error, {:live_redirect, %{to: _target}}} =
               view
               |> form("#transport-profile-form",
                 transport_profile: %{
                   display_name: "TC Uplink Gateway",
                   family_key: "uplink_gateway",
                   target_scope: "path",
                   service_name: "commanding",
                   frame_size: "128",
                   scid: "",
                   vcid: "2",
                   bypass_flag: "0",
                   control_command_flag: "0",
                   segment_header_flag: "0",
                   initial_frame_seq: "7",
                   cop1_mode: "fop",
                   cop1_timeout_ms: "3000",
                   cop1_max_retransmit: "5",
                   cop1_window_size: "1",
                   simulated_start_delay_ms: "",
                   simulated_completion_delay_ms: "250"
                 }
               )
               |> render_submit()

      [transport] = Cadence.list_transport_profiles(org.organization_id, mission.mission_id)
      assert transport.family_key == :uplink_gateway
      assert transport.configuration["service_name"] == "commanding"
      assert transport.configuration["frame_size"] == 128
      refute Map.has_key?(transport.configuration, "scid")
      assert transport.configuration["vcid"] == 2
      assert transport.configuration["initial_frame_seq"] == 7
      assert transport.configuration["cop1_mode"] == "fop"
      assert transport.configuration["cop1_timeout_ms"] == 3000
      assert transport.configuration["cop1_max_retransmit"] == 5
      assert transport.configuration["simulated_completion_delay_ms"] == 250
    end

    test "shows and versions protocol behaviors" do
      {conn, org, mission} = signed_in_org_and_mission()

      transport =
        TransportProfile.new(%{
          mission_id: mission.mission_id,
          family_key: :heartbeat_monitor,
          target_scope: :path,
          configuration: %{"heartbeat_interval_ms" => 1000},
          metadata: %{"display_name" => "Heartbeat Monitor"}
        })

      assert {:ok, transport} = Cadence.persist_transport_profile(org.organization_id, transport)

      {:ok, show_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/#{transport.transport_profile_id}"
        )

      assert has_element?(show_view, "#comms-transport-profile-show-page")
      assert html =~ "Heartbeat Monitor"
      assert html =~ "Heartbeat every 1000 ms"
      assert html =~ "Version History"

      {:ok, version_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/#{transport.transport_profile_id}/new-version"
        )

      assert html =~ "New Protocol Behavior Version"

      assert has_element?(
               version_view,
               "input[name='transport_profile[heartbeat_interval_ms]'][value='1000']"
             )

      assert {:error, {:live_redirect, %{to: target}}} =
               version_view
               |> form("#transport-profile-form",
                 transport_profile: %{
                   display_name: "Heartbeat Monitor",
                   family_key: "heartbeat_monitor",
                   target_scope: "transport",
                   heartbeat_interval_ms: "2000"
                 }
               )
               |> render_submit()

      assert target ==
               ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/#{transport.transport_profile_id}"

      [v2, v1] =
        Cadence.list_transport_profile_versions(
          org.organization_id,
          mission.mission_id,
          transport.transport_profile_id
        )

      assert v1.version == 1
      assert v2.version == 2
      assert v2.target_scope == :transport
      assert v2.configuration["heartbeat_interval_ms"] == 2000
    end

    test "archives unreferenced providers, protocol behaviors, and link templates" do
      {conn, org, mission} = signed_in_org_and_mission()

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          metadata: %{"display_name" => "Unused Provider"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      {:ok, provider_view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}"
        )

      assert {:error, {:live_redirect, %{to: provider_target}}} =
               provider_view
               |> element("#archive-provider-profile-button")
               |> render_click()

      assert provider_target == ~p"/missions/#{mission.mission_id}/comms/providers"
      assert Cadence.list_provider_profiles(org.organization_id, mission.mission_id) == []

      [archived_provider, original_provider] =
        Cadence.list_provider_profile_versions(
          org.organization_id,
          mission.mission_id,
          provider.provider_profile_id
        )

      assert original_provider.lifecycle_state == :active
      assert archived_provider.lifecycle_state == :deleted

      transport =
        TransportProfile.new(%{
          mission_id: mission.mission_id,
          family_key: :heartbeat_monitor,
          target_scope: :path,
          configuration: %{"heartbeat_interval_ms" => 1000},
          metadata: %{"display_name" => "Unused Transport"}
        })

      assert {:ok, transport} = Cadence.persist_transport_profile(org.organization_id, transport)

      {:ok, transport_view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/#{transport.transport_profile_id}"
        )

      assert {:error, {:live_redirect, %{to: transport_target}}} =
               transport_view
               |> element("#archive-transport-profile-button")
               |> render_click()

      assert transport_target == ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors"
      assert Cadence.list_transport_profiles(org.organization_id, mission.mission_id) == []

      [archived_transport, original_transport] =
        Cadence.list_transport_profile_versions(
          org.organization_id,
          mission.mission_id,
          transport.transport_profile_id
        )

      assert original_transport.lifecycle_state == :active
      assert archived_transport.lifecycle_state == :deleted

      endpoint =
        SourceEndpoint.new(%{
          mission_id: mission.mission_id,
          display_name: "Archive endpoint",
          source_ref: "archive"
        })

      assert {:ok, endpoint} = Cadence.persist_source_endpoint(org.organization_id, endpoint)

      path_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :candidate,
          source_endpoint_ref: endpoint.source_endpoint_id,
          metadata: %{"display_name" => "Archive path"}
        })

      assert {:ok, path_template} =
               Cadence.persist_path_template(org.organization_id, path_template)

      {:ok, path_view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/link-templates/#{path_template.path_template_id}"
        )

      assert {:error, {:live_redirect, %{to: path_target}}} =
               path_view
               |> element("#archive-path-template-button")
               |> render_click()

      assert path_target == ~p"/missions/#{mission.mission_id}/comms/link-templates"
      assert Cadence.list_path_templates(org.organization_id, mission.mission_id) == []

      [archived_path, original_path] =
        Cadence.list_path_template_versions(
          org.organization_id,
          mission.mission_id,
          path_template.path_template_id
        )

      assert original_path.lifecycle_state == :active
      assert archived_path.lifecycle_state == :deleted
    end

    test "blocks archiving profiles used by active paths" do
      {conn, org, mission} = signed_in_org_and_mission()
      setup = persist_complete_comms_setup!(org, mission)

      {:ok, provider_view, provider_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{setup.provider.provider_profile_id}"
        )

      assert provider_html =~ "Archive Blocked By Active Paths"

      provider_result =
        provider_view
        |> element("#archive-provider-profile-button")
        |> render_click()

      assert provider_result =~ "Provider is still referenced by active link templates."

      assert {:ok, _provider} =
               Cadence.fetch_provider_profile(
                 org.organization_id,
                 mission.mission_id,
                 setup.provider.provider_profile_id
               )

      {:ok, transport_view, transport_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/protocol-behaviors/#{setup.transport.transport_profile_id}"
        )

      assert transport_html =~ "Archive Blocked By Active Paths"

      transport_result =
        transport_view
        |> element("#archive-transport-profile-button")
        |> render_click()

      assert transport_result =~ "Protocol behavior is still referenced by active link templates."

      assert {:ok, _transport} =
               Cadence.fetch_transport_profile(
                 org.organization_id,
                 mission.mission_id,
                 setup.transport.transport_profile_id
               )
    end

    test "rejects invalid provider TCP configuration" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

      html =
        view
        |> form("#provider-profile-form",
          provider_profile: %{
            display_name: "Bad Provider",
            tcp_mode: "connect",
            direction: "downlink",
            host: "ground.example",
            port: "70000",
            framing_mode: "raw",
            reconnect_policy: "always",
            tls_enabled: "false"
          }
        )
        |> render_submit()

      assert html =~ "Port must be an integer from 1 to 65535."
    end

    test "creates TCP client providers with reconnect and TLS settings" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

      assert html =~ "TCP Mode"
      assert html =~ "Advanced Configuration Preview"

      assert {:error, {:live_redirect, %{to: _target}}} =
               view
               |> form("#provider-profile-form",
                 provider_profile: %{
                   display_name: "TCP Client Provider",
                   tcp_mode: "connect",
                   direction: "uplink",
                   host: "ground.example",
                   port: "6000",
                   framing_mode: "line_delimited",
                   reconnect_policy: "always",
                   tls_enabled: "true"
                 }
               )
               |> render_submit()

      [provider] = Cadence.list_provider_profiles(org.organization_id, mission.mission_id)
      assert provider.configuration["mode"] == "connect"
      assert provider.configuration["direction"] == "uplink"
      assert provider.configuration["host"] == "ground.example"
      assert provider.configuration["port"] == 6000
      assert provider.configuration["framing"] == %{"mode" => "line_delimited"}
      assert provider.configuration["reconnect"] == %{"policy" => "always"}
      assert provider.configuration["tls"] == %{"enabled" => true}
    end

    test "shows and versions TCP providers" do
      {conn, org, mission} = signed_in_org_and_mission()

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          configuration: %{
            "adapter" => "tcp_socket",
            "mode" => "listen",
            "direction" => "downlink",
            "host" => "127.0.0.1",
            "port" => 5000,
            "framing" => %{"mode" => "raw"},
            "tls" => %{"enabled" => false},
            "reconnect" => %{"policy" => "on_disconnect"}
          },
          metadata: %{"display_name" => "TCP Provider"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      {:ok, show_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}"
        )

      assert has_element?(show_view, "#comms-provider-profile-show-page")
      assert html =~ "TCP Provider"
      assert html =~ "127.0.0.1:5000"
      assert html =~ "Version History"

      {:ok, version_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}/new-version"
        )

      assert html =~ "New Provider Version"

      assert has_element?(
               version_view,
               "input[name='provider_profile[port]'][value='5000']"
             )

      assert {:error, {:live_redirect, %{to: target}}} =
               version_view
               |> form("#provider-profile-form",
                 provider_profile: %{
                   display_name: "TCP Provider",
                   tcp_mode: "listen",
                   direction: "downlink",
                   host: "127.0.0.1",
                   port: "5100",
                   framing_mode: "fixed_size",
                   frame_size: "32",
                   reconnect_policy: "on_disconnect",
                   tls_enabled: "true"
                 }
               )
               |> render_submit()

      assert target ==
               ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}"

      [v2, v1] =
        Cadence.list_provider_profile_versions(
          org.organization_id,
          mission.mission_id,
          provider.provider_profile_id
        )

      assert v1.version == 1
      assert v2.version == 2
      assert v2.configuration["port"] == 5100
      assert v2.configuration["fixed_message_bytes"] == 32
      assert v2.configuration["tls"] == %{"enabled" => true}
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/some-mission-id/comms")
    end
  end
end
