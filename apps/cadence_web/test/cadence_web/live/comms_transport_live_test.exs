defmodule CadenceWeb.CommsTransportLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.Transport
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "primary",
        display_name: "Primary Mission"
      )

    {TestFixtures.member_conn(user), organization, mission}
  end

  describe "transport routes" do
    test "renders the empty state when the mission has no transports" do
      {conn, _organization, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      assert has_element?(view, "#comms-transports-page", "No transports")
      assert has_element?(view, "#new-transport-link")
      refute has_element?(view, "#transports-list-component")
    end

    test "lists transports with origin, operator summary, and readiness" do
      {conn, organization, mission} = signed_in_org_and_mission()
      transport = persist_transport!(organization.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      assert has_element?(view, "#comms-transports-page")
      assert has_element?(view, "#new-transport-link")
      assert has_element?(view, "#transports-list-component")
      refute has_element?(view, "#comms-transports-page", "Link Assignment")
      refute has_element?(view, "#comms-transports-page", "Link Template")

      sidebar = LiveVue.Test.get_vue(view, id: "mission-sidebar-navigation")

      comms =
        Enum.find(
          sidebar.props["presentation"]["navigation"]["items"],
          &(&1["key"] == "comms")
        )

      transports = Enum.find(comms["children"], &(&1["key"] == "comms-transports"))

      assert comms["expanded"]
      assert transports["active"]
      assert transports["label"] == "Transports"

      vue = LiveVue.Test.get_vue(view, id: "transports-list-component")

      assert vue.component == "CommsTransportList"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "rows" => [
                 %{
                   "id" => "transport-#{transport.transport_id}",
                   "transport_id" => transport.transport_id,
                   "display_name" => transport.display_name,
                   "origin" => "Direct",
                   "origin_id" => "transport-origin-#{transport.transport_id}",
                   "provider" => "Cadence",
                   "provider_dom_id" => "transport-provider-#{transport.transport_id}",
                   "operator_summary" => "Direct TCP SOCKET",
                   "operator_summary_id" =>
                     "transport-operator-summary-#{transport.transport_id}",
                   "endpoint" => "0.0.0.0:5000",
                   "readiness_status" => "info",
                   "readiness_label" => "Configured",
                   "readiness_id" => "transport-readiness-#{transport.transport_id}",
                   "version" => "v1",
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/transports/#{transport.transport_id}"
                 }
               ],
               "search" => nil,
               "sort" => "display_name",
               "sort_dir" => "asc",
               "page" => 1,
               "page_size" => 50,
               "total_count" => 1
             }
    end

    test "search narrows the transport list" do
      {conn, organization, mission} = signed_in_org_and_mission()
      _lab = persist_transport!(organization.organization_id, mission.mission_id, "Lab TCP")

      _ground =
        persist_transport!(organization.organization_id, mission.mission_id, "Ground Uplink")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      initial_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")

      assert Enum.map(initial_vue.props["rows"], & &1["display_name"]) == [
               "Ground Uplink",
               "Lab TCP"
             ]

      render_hook(view, "search", %{"q" => "ground"})

      search_path = "/missions/#{mission.mission_id}/comms/transports?q=ground"

      assert_patch(view, search_path)
      render_patch(view, search_path)

      searched_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")

      assert searched_vue.props["search"] == "ground"
      assert searched_vue.props["total_count"] == 1
      assert Enum.map(searched_vue.props["rows"], & &1["display_name"]) == ["Ground Uplink"]

      render_hook(view, "search", %{"q" => "no-such-transport"})

      no_match_path =
        "/missions/#{mission.mission_id}/comms/transports?q=no-such-transport"

      assert_patch(view, no_match_path)
      render_patch(view, no_match_path)

      no_matches_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")
      assert no_matches_vue.props["search"] == "no-such-transport"
      assert no_matches_vue.props["total_count"] == 0
      assert no_matches_vue.props["rows"] == []
    end

    test "sorts through the LiveView-owned list event" do
      {conn, organization, mission} = signed_in_org_and_mission()
      alpha = persist_transport!(organization.organization_id, mission.mission_id, "Alpha TCP")
      zulu = persist_transport!(organization.organization_id, mission.mission_id, "Zulu TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      initial_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")

      assert Enum.map(initial_vue.props["rows"], & &1["transport_id"]) == [
               alpha.transport_id,
               zulu.transport_id
             ]

      render_hook(view, "sort", %{"sort" => "display_name"})

      sort_path =
        "/missions/#{mission.mission_id}/comms/transports?sort=display_name&dir=desc"

      assert_patch(view, sort_path)
      render_patch(view, sort_path)

      sorted_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")
      assert sorted_vue.props["sort"] == "display_name"
      assert sorted_vue.props["sort_dir"] == "desc"

      assert Enum.map(sorted_vue.props["rows"], & &1["transport_id"]) == [
               zulu.transport_id,
               alpha.transport_id
             ]
    end

    test "paginates through the LiveView event and keeps visible rows in props" do
      {conn, organization, mission} = signed_in_org_and_mission()

      for transport_number <- 1..51 do
        suffix = transport_number |> Integer.to_string() |> String.pad_leading(2, "0")

        persist_transport!(
          organization.organization_id,
          mission.mission_id,
          "Transport #{suffix}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      first_page_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")
      assert first_page_vue.props["page"] == 1
      assert first_page_vue.props["total_count"] == 51
      assert length(first_page_vue.props["rows"]) == 50

      render_hook(view, "paginate", %{"page" => "2"})

      second_page_path = "/missions/#{mission.mission_id}/comms/transports?page=2"

      assert_patch(view, second_page_path)
      render_patch(view, second_page_path)

      second_page_vue = LiveVue.Test.get_vue(view, id: "transports-list-component")
      assert second_page_vue.props["page"] == 2
      assert second_page_vue.props["total_count"] == 51
      assert Enum.map(second_page_vue.props["rows"], & &1["display_name"]) == ["Transport 51"]
    end

    test "progressively configures and shows a direct TCP transport" do
      {conn, organization, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      assert has_element?(view, "#comms-transport-new-component")

      vue = LiveVue.Test.get_vue(view, id: "comms-transport-new-component")

      assert vue.component == "CommsTransportNew"
      assert vue.ssr == false
      assert vue.class == "contents"
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      assert vue.handlers == %{
               "save" => Phoenix.LiveView.JS.push("save"),
               "validate" => Phoenix.LiveView.JS.push("validate")
             }

      assert vue.props["page"] == %{
               "id" => "comms-transport-new-page",
               "title" => "New Transport",
               "subtitle" =>
                 "Describe a durable byte-moving capability. This setup does not mean a connection is currently open.",
               "breadcrumbs" => [
                 %{
                   "label" => mission.display_name,
                   "href" => "/missions/#{mission.mission_id}"
                 },
                 %{
                   "label" => "Comms",
                   "href" => "/missions/#{mission.mission_id}/comms"
                 },
                 %{
                   "label" => "Transports",
                   "href" => "/missions/#{mission.mission_id}/comms/transports"
                 },
                 %{"label" => "New Transport", "href" => nil}
               ]
             }

      initial_form = vue.props["form"]
      assert initial_form["id"] == "transport-form"
      assert initial_form["selected_origin"] == "direct"
      refute initial_form["can_submit"]
      assert initial_form["provider"]["active"] == false
      assert initial_form["direct_configuration"]["active"] == true

      assert initial_form["sections"] == %{
               "identity" => %{
                 "id" => "transport-identity-section",
                 "number" => "01",
                 "title" => "Identity"
               },
               "origin" => %{
                 "id" => "transport-origin-section",
                 "number" => "02",
                 "title" => "Origin"
               },
               "source" => %{
                 "id" => "transport-source-section",
                 "number" => "03",
                 "title" => "Source"
               },
               "provider_capability" => %{
                 "id" => "transport-capability-section",
                 "number" => "04",
                 "title" => "Capability"
               },
               "review" => %{
                 "id" => "transport-summary-section",
                 "number" => "06",
                 "title" => "Review"
               }
             }

      assert initial_form["fields"]["display_name"]
             |> Map.take(["id", "name", "type", "label", "required", "value"]) == %{
               "id" => "transport-display-name",
               "name" => "transport[display_name]",
               "type" => "text",
               "label" => "Display Name",
               "required" => true,
               "value" => ""
             }

      assert initial_form["fields"]["origin"]["options"] == [
               %{
                 "label" => "Direct — configured in Cadence",
                 "value" => "direct",
                 "disabled" => false
               },
               %{
                 "label" => "Ground Station Provider",
                 "value" => "provider_managed",
                 "disabled" => false
               }
             ]

      assert initial_form["actions"] == %{
               "submit" => %{
                 "id" => "create-transport-button",
                 "label" => "Create Transport"
               },
               "cancel" => %{
                 "id" => "cancel-transport-link",
                 "label" => "Cancel",
                 "href" => "/missions/#{mission.mission_id}/comms/transports"
               }
             }

      assert initial_form["direct_configuration"]
             |> Map.take(["id", "kind", "description"]) == %{
               "id" => "transport-direct-configuration",
               "kind" => "transport_kind",
               "description" =>
                 "Cadence owns this endpoint, framing boundary, and reconnect behavior."
             }

      assert Enum.map(initial_form["direct_configuration"]["sections"], fn section ->
               {section["id"], section["fields_id"], section["number"], section["title"]}
             end) == [
               {"transport-capability-section", "transport-capability-section-fields", "04",
                "TCP Capability"},
               {"transport-framing-section", "transport-framing-section-fields", "05", "Framing"},
               {"transport-reliability-section", "transport-reliability-section-fields", "05B",
                "Reliability"}
             ]

      initial_configuration_fields =
        initial_form["direct_configuration"]["sections"]
        |> Enum.flat_map(& &1["fields"])
        |> Map.new(&{&1["key"], &1})

      assert initial_configuration_fields["tcp_mode"]["value"] == "listen"
      assert initial_configuration_fields["direction_capability"]["value"] == "inbound"
      assert initial_configuration_fields["host"]["value"] == "0.0.0.0"
      assert initial_configuration_fields["port"]["min"] == 1
      assert initial_configuration_fields["port"]["max"] == 65_535
      assert initial_configuration_fields["framing_mode"]["value"] == "raw"
      refute initial_configuration_fields["frame_size"]["visible"]
      refute initial_configuration_fields["reconnect_policy"]["visible"]
      assert initial_configuration_fields["tls_enabled"]["value"] == "false"

      progressive_payload = %{
        "transport" => %{
          "display_name" => "AI&T TCP",
          "origin" => "direct",
          "transport_kind" => "tcp_socket",
          "tcp_mode" => "connect",
          "direction_capability" => "inbound",
          "host" => "lab.example",
          "port" => "5001",
          "framing_mode" => "fixed_size",
          "tls_enabled" => "false"
        }
      }

      render_hook(view, "validate", progressive_payload)

      progressive_vue = LiveVue.Test.get_vue(view, id: "comms-transport-new-component")

      progressive_fields =
        progressive_vue.props["form"]["direct_configuration"]["sections"]
        |> Enum.flat_map(& &1["fields"])
        |> Map.new(&{&1["key"], &1})

      assert progressive_fields["frame_size"]["visible"]

      assert progressive_fields["frame_size"]["visible_when"] == %{
               "field" => "framing_mode",
               "equals" => "fixed_size"
             }

      assert progressive_fields["reconnect_policy"]["visible"]

      assert progressive_fields["reconnect_policy"]["visible_when"] == %{
               "field" => "tcp_mode",
               "equals" => "connect"
             }

      direct_params =
        direct_transport_params()
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

      assert direct_params == %{
               "display_name" => "AI&T TCP",
               "origin" => "direct",
               "transport_kind" => "tcp_socket",
               "tcp_mode" => "connect",
               "direction_capability" => "inbound",
               "host" => "lab.example",
               "port" => "5001",
               "framing_mode" => "fixed_size",
               "frame_size" => "64",
               "reconnect_policy" => "always",
               "tls_enabled" => "false"
             }

      render_hook(view, "validate", %{"transport" => direct_params})

      ready_vue = LiveVue.Test.get_vue(view, id: "comms-transport-new-component")
      assert ready_vue.props["form"]["can_submit"]
      assert ready_vue.props["form"]["review"]["readiness"]["value"] == "Ready to save"
      assert ready_vue.props["form"]["review"]["readiness"]["endpoint"] == "lab.example:5001"

      render_hook(view, "save", %{"transport" => direct_params})
      {target, _flash} = assert_redirect(view)

      [transport] =
        TransportStore.list_transports(
          organization.organization_id,
          mission.mission_id
        )

      assert transport.display_name == "AI&T TCP"
      assert transport.origin == :direct
      assert transport.direction_capability == :inbound
      assert transport.configuration["host"] == "lab.example"
      assert is_binary(transport.materialized_provider_profile_id)

      {:ok, show_view, _show_html} = live(conn, target)
      assert has_element?(show_view, "#comms-transport-show-page")
      assert has_element?(show_view, "#comms-transport-show-component")

      vue = transport_show_vue(show_view)

      assert vue.component == "CommsTransportShow"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "navigation" => %{
                 "breadcrumbs" => [
                   %{
                     "href" => "/missions/#{mission.mission_id}",
                     "label" => mission.display_name
                   },
                   %{
                     "href" => "/missions/#{mission.mission_id}/comms",
                     "label" => "Comms"
                   },
                   %{
                     "href" => "/missions/#{mission.mission_id}/comms/transports",
                     "label" => "Transports"
                   },
                   %{"href" => nil, "label" => transport.display_name}
                 ]
               },
               "transport" => %{
                 "capability" => %{
                   "description" =>
                     "Durable transport setup. Runtime Links and Contacts are realized later under execution context.",
                   "details" => [
                     detail_props("Origin", "Direct"),
                     detail_props("Direction Capability", "INBOUND"),
                     detail_props("Mode", "CONNECT"),
                     detail_props("Framing", "FIXED SIZE"),
                     detail_props("TLS", "Disabled"),
                     detail_props("Readiness", "Configured")
                   ],
                   "diagnostics" => %{
                     "id" => "transport-admin-diagnostics",
                     "json" => diagnostics_json(transport),
                     "json_id" => "transport-admin-diagnostics-json",
                     "label" => "Administrator Diagnostics"
                   },
                   "endpoint" => "lab.example:5001",
                   "eyebrow" => "Byte-Moving Capability",
                   "kind" => "TCP SOCKET"
                 },
                 "display_name" => transport.display_name,
                 "origin_badge" => %{
                   "id" => "transport-origin-badge",
                   "label" => "Direct"
                 },
                 "summary_tiles" => [
                   %{
                     "id" => "transport-origin-summary",
                     "label" => "Origin",
                     "value" => "Direct"
                   },
                   %{
                     "id" => "transport-provider-summary",
                     "label" => "Provider",
                     "value" => "Cadence"
                   },
                   %{
                     "id" => "transport-operator-summary",
                     "label" => "Delivery",
                     "value" => "Direct TCP SOCKET"
                   },
                   %{
                     "id" => "transport-readiness-summary",
                     "label" => "Readiness",
                     "value" => "Configured"
                   }
                 ],
                 "transport_id" => transport.transport_id,
                 "version" => "v1"
               },
               "version_history" => %{
                 "id" => "transport-versions",
                 "rows" => [
                   %{
                     "id" => "transport-version-1",
                     "label" => "v1",
                     "lifecycle_state" => "ACTIVE"
                   }
                 ],
                 "title" => "Version History"
               }
             }

      refute has_element?(show_view, "#comms-transport-show-page", "Link Template")
    end

    test "derives a provider-managed Transport from compatible synchronized profiles" do
      {conn, organization, mission} = signed_in_org_and_mission()
      provider = persist_ready_provider!(organization.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      validate_payload = %{
        "transport" => %{
          "display_name" => "Provider Downlink",
          "origin" => "provider_managed",
          "transport_kind" => "tcp_socket",
          "tcp_mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      }

      render_hook(view, "validate", validate_payload)

      vue = LiveVue.Test.get_vue(view, id: "comms-transport-new-component")
      assert vue.component == "CommsTransportNew"
      assert vue.ssr == false
      assert vue.class == "contents"
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      form = vue.props["form"]
      assert form["selected_origin"] == "provider_managed"
      assert form["provider"]["active"]
      refute form["direct_configuration"]["active"]

      assert form["fields"]["transport_kind"]["provider_managed_id"] ==
               "transport-kind-provider-managed"

      assert form["fields"]["transport_kind"]["value"] == "tcp_socket"

      assert form["fields"]["mission_provider_id"]["options"] == [
               %{
                 "label" => "#{provider.display_name} · v#{provider.version}",
                 "value" => provider.provider_id,
                 "disabled" => false
               }
             ]

      assert form["provider"]["selected"] == %{
               "display_name" => provider.display_name,
               "version" => provider.version,
               "status" => "ready",
               "status_label" => "Profiles synced"
             }

      service_token = form["fields"]["service_profile_id"]["value"]
      delivery_token = form["fields"]["delivery_profile_id"]["value"]

      assert form["fields"]["service_profile_id"]["options"] == [
               %{
                 "label" => "Realtime telemetry · v3",
                 "value" => service_token,
                 "disabled" => false
               }
             ]

      assert form["fields"]["delivery_profile_id"]["options"] == [
               %{
                 "label" => "Streaming to Cadence",
                 "value" => delivery_token,
                 "disabled" => false
               }
             ]

      assert form["provider"]["operator_summary"] == %{
               "id" => "transport-provider-operator-summary",
               "label" => "Operator Summary",
               "text" => "Streaming to Cadence",
               "endpoint" => "127.0.0.1:5100"
             }

      assert form["provider_derived"]
             |> Map.take(["active", "id", "number", "title", "description"]) == %{
               "active" => true,
               "id" => "transport-provider-derived-section",
               "number" => "05",
               "title" => "Provider-Derived Runtime",
               "description" =>
                 "Endpoint, framing, and reliability are provider-owned for this Transport and remain read-only."
             }

      assert form["provider_derived"]["configuration"] == %{
               "id" => "transport-provider-derived-configuration",
               "empty_text" => nil,
               "rows" => [
                 %{"label" => "Actual kind", "value" => "TCP socket", "mono" => false},
                 %{"label" => "Mode", "value" => "LISTEN", "mono" => false},
                 %{"label" => "Direction", "value" => "INBOUND", "mono" => false},
                 %{"label" => "Endpoint", "value" => "127.0.0.1:5100", "mono" => true},
                 %{"label" => "Framing", "value" => "FIXED SIZE", "mono" => false},
                 %{"label" => "TLS", "value" => "Disabled", "mono" => false}
               ]
             }

      assert form["can_submit"]
      refute Jason.encode!(vue.props) =~ "config://simulator"
      refute Map.has_key?(form["provider"]["selected"], "credential_ref")

      save_payload = %{
        "transport" => %{
          "display_name" => "Provider Downlink",
          "origin" => "provider_managed",
          "transport_kind" => "tcp_socket",
          "mission_provider_id" => provider.provider_id,
          "service_profile_id" => service_token,
          "delivery_profile_id" => delivery_token
        }
      }

      render_hook(view, "save", save_payload)
      {target, _flash} = assert_redirect(view)

      [transport] =
        TransportStore.list_transports(
          organization.organization_id,
          mission.mission_id
        )

      assert transport.origin == :provider_managed
      assert transport.mission_provider_id == provider.provider_id
      assert transport.mission_provider_version == provider.version
      assert transport.service_profile_ref == %{"id" => "service-downlink", "version" => 3}
      assert transport.delivery_profile_ref == %{"id" => "delivery-cadence", "version" => 7}
      assert transport.configuration["host"] == "127.0.0.1"

      {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      list_vue = LiveVue.Test.get_vue(list_view, id: "transports-list-component")
      assert [transport_row] = list_vue.props["rows"]
      assert transport_row["id"] == "transport-#{transport.transport_id}"
      assert transport_row["origin"] == "Provider managed"
      assert transport_row["origin_id"] == "transport-origin-#{transport.transport_id}"
      assert transport_row["provider"] == provider.display_name

      assert transport_row["provider_dom_id"] ==
               "transport-provider-#{transport.transport_id}"

      assert transport_row["operator_summary"] == "Streaming to Cadence"

      assert transport_row["operator_summary_id"] ==
               "transport-operator-summary-#{transport.transport_id}"

      assert transport_row["endpoint"] == "127.0.0.1:5100"
      assert transport_row["readiness_status"] == "ready"
      assert transport_row["readiness_label"] == "Ready"
      assert transport_row["readiness_id"] == "transport-readiness-#{transport.transport_id}"

      {:ok, show_view, _show_html} = live(conn, target)
      vue = transport_show_vue(show_view)

      assert vue.component == "CommsTransportShow"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props["transport"]["origin_badge"] == %{
               "id" => "transport-origin-badge",
               "label" => "Provider managed"
             }

      assert vue.props["transport"]["summary_tiles"] == [
               %{
                 "id" => "transport-origin-summary",
                 "label" => "Origin",
                 "value" => "Provider managed"
               },
               %{
                 "id" => "transport-provider-summary",
                 "label" => "Provider",
                 "value" => provider.display_name
               },
               %{
                 "id" => "transport-operator-summary",
                 "label" => "Delivery",
                 "value" => "Streaming to Cadence"
               },
               %{
                 "id" => "transport-readiness-summary",
                 "label" => "Readiness",
                 "value" => "Ready"
               }
             ]

      assert vue.props["transport"]["capability"]["details"] == [
               detail_props("Origin", "Provider managed"),
               detail_props(
                 "Mission Provider",
                 "#{provider.display_name} · v#{provider.version}",
                 href: "/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
               ),
               detail_props("Service Profile", "service-downlink · v3", mono: true),
               detail_props("Delivery Profile", "delivery-cadence · v7", mono: true),
               detail_props("Direction Capability", "INBOUND"),
               detail_props("Mode", "LISTEN"),
               detail_props("Framing", "FIXED SIZE"),
               detail_props("TLS", "Disabled"),
               detail_props("Readiness", "Ready")
             ]
    end

    test "missing transport redirects to the current mission transport list" do
      {conn, _organization, mission} = signed_in_org_and_mission()

      assert {:error,
              {:live_redirect,
               %{
                 to: to,
                 flash: %{"error" => "Transport not found."}
               }}} =
               live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/missing")

      assert to == ~p"/missions/#{mission.mission_id}/comms/transports"
    end

    test "does not expose transports outside the current organization or mission scope" do
      {conn, organization, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(organization,
          slug: "secondary",
          display_name: "Secondary Mission"
        )

      other_mission_transport =
        persist_transport!(
          organization.organization_id,
          other_mission.mission_id,
          "Sibling TCP"
        )

      other_organization =
        TestFixtures.persist_org!(display_name: "Remote Org", slug: "remote-org")

      remote_mission = TestFixtures.persist_mission!(other_organization, slug: "remote")

      other_organization_transport =
        persist_transport!(
          other_organization.organization_id,
          remote_mission.mission_id,
          "Remote TCP"
        )

      for foreign_transport <- [other_mission_transport, other_organization_transport] do
        assert {:error,
                {:live_redirect,
                 %{
                   to: to,
                   flash: %{"error" => "Transport not found."}
                 }}} =
                 live(
                   conn,
                   ~p"/missions/#{mission.mission_id}/comms/transports/#{foreign_transport.transport_id}"
                 )

        assert to == ~p"/missions/#{mission.mission_id}/comms/transports"
      end
    end

    test "keeps unvalidated providers out of the selectable provider flow" do
      {conn, organization, mission} = signed_in_org_and_mission()
      provider = persist_unvalidated_provider!(organization.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      payload = %{
        "transport" => %{
          "display_name" => "Downlink",
          "origin" => "provider_managed",
          "transport_kind" => "tcp_socket",
          "tcp_mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      }

      render_hook(view, "validate", payload)

      vue = LiveVue.Test.get_vue(view, id: "comms-transport-new-component")
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      form = vue.props["form"]
      assert form["provider"]["active"]
      assert form["provider"]["ready_count"] == 0
      assert form["provider"]["empty_state"]["visible"]
      assert form["provider"]["selected"] == nil
      assert form["fields"]["service_profile_id"]["options"] == []
      assert form["fields"]["delivery_profile_id"]["options"] == []

      assert Enum.find(
               form["fields"]["mission_provider_id"]["options"],
               &(&1["value"] == provider.provider_id)
             ) == %{
               "label" => "#{provider.display_name} · v#{provider.version}",
               "value" => provider.provider_id,
               "disabled" => true
             }

      refute form["can_submit"]

      assert form["actions"]["submit"] == %{
               "id" => "create-transport-button",
               "label" => "Create Transport"
             }
    end

    test "renders a stable validation outcome for invalid direct TCP setup" do
      {conn, _organization, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      payload = %{
        "transport" => %{
          "display_name" => "Bad TCP",
          "origin" => "direct",
          "transport_kind" => "tcp_socket",
          "tcp_mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "70000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      }

      render_hook(view, "save", payload)

      vue = LiveVue.Test.get_vue(view, id: "comms-transport-new-component")
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))
      refute vue.props["form"]["can_submit"]

      invalid_port_field =
        vue.props["form"]["direct_configuration"]["sections"]
        |> Enum.flat_map(& &1["fields"])
        |> Enum.find(&(&1["key"] == "port"))

      assert invalid_port_field["value"] == "70000"
      assert vue.props["form"]["review"]["error_id"] == "transport-form-error"

      assert vue.props["form"]["review"]["error"] ==
               "Port must be an integer from 1 to 65535."

      assert vue.props["form"]["review"]["readiness"] == %{
               "label" => "Readiness",
               "status" => "attention",
               "value" => "Incomplete",
               "endpoint" => "Endpoint not yet resolved"
             }

      assert TransportStore.list_transports(
               mission.organization_id,
               mission.mission_id
             ) == []
    end
  end

  defp transport_show_vue(view) do
    LiveVue.Test.get_vue(view, id: "comms-transport-show-component")
  end

  defp detail_props(label, value, opts \\ []) do
    %{
      "href" => Keyword.get(opts, :href),
      "label" => label,
      "mono" => Keyword.get(opts, :mono, false),
      "value" => value
    }
  end

  defp diagnostics_json(transport) do
    Jason.encode!(
      %{
        "origin" => Atom.to_string(transport.origin),
        "configuration" => transport.configuration,
        "provider_configuration_snapshot" => transport.provider_configuration_snapshot,
        "compatibility_provider_profile_id" => transport.materialized_provider_profile_id
      },
      pretty: true
    )
  end

  defp direct_transport_params do
    %{
      display_name: "AI&T TCP",
      origin: "direct",
      transport_kind: "tcp_socket",
      tcp_mode: "connect",
      direction_capability: "inbound",
      host: "lab.example",
      port: "5001",
      framing_mode: "fixed_size",
      frame_size: "64",
      reconnect_policy: "always",
      tls_enabled: "false"
    }
  end

  defp persist_transport!(organization_id, mission_id, display_name) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: display_name,
        origin: :direct,
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, persisted} =
             TransportStore.persist_transport(organization_id, transport)

    persisted
  end

  defp persist_ready_provider!(organization_id, mission_id) do
    provider = provider_fixture(mission_id, ready?: true)
    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp persist_unvalidated_provider!(organization_id, mission_id) do
    provider = provider_fixture(mission_id, ready?: false)
    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp provider_fixture(mission_id, opts) do
    ready? = Keyword.fetch!(opts, :ready?)
    now = ~U[2026-07-14 12:00:00.000000Z]

    MissionProvider.new(%{
      mission_id: mission_id,
      display_name: if(ready?, do: "Ground Network Simulator", else: "Unvalidated Simulator"),
      provider_type: :simulator,
      base_url: "http://127.0.0.1:4101",
      credential_ref: "config://simulator",
      environment_ref: "local",
      last_validated_at: if(ready?, do: now),
      last_synced_at: if(ready?, do: now),
      metadata: if(ready?, do: %{"control_plane" => %{"status" => "healthy"}}, else: %{}),
      inventory_sync_document: if(ready?, do: provider_inventory(), else: %{})
    })
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-downlink",
            "version" => 3,
            "display_name" => "Realtime telemetry",
            "direction" => "downlink",
            "state" => "active"
          }
        ]
      },
      "delivery_profiles" => %{
        "items" => [
          %{
            "id" => "delivery-cadence",
            "version" => 7,
            "display_name" => "Cadence ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-downlink"],
            "state" => "ready",
            "operator_summary" => "Streaming to Cadence",
            "diagnostics" => %{
              "protocol" => "tcp",
              "mode" => "provider_connects",
              "host" => "127.0.0.1",
              "port" => 5100,
              "framing_family" => "ccsds_tm",
              "frame_bytes" => 1115,
              "endpoint_health" => "healthy"
            }
          }
        ]
      }
    }
  end
end
