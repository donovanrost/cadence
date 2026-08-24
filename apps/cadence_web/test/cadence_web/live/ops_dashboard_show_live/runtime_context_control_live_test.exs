defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextControlLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Comms.TransportStore

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
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

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp context_selector_presentation(view) do
    dashboard_context_selector_presentation(view)
  end

  defp find_context_node(%{"attrs" => attrs} = node, attribute, value) do
    if attrs[attribute] == value do
      node
    else
      Enum.find_value(node["children"], fn
        child when is_map(child) -> find_context_node(child, attribute, value)
        _text -> nil
      end)
    end
  end

  defp find_context_node(%{"key" => key} = node, key), do: node

  defp find_context_node(%{"children" => children}, key) do
    Enum.find_value(children, fn
      child when is_map(child) -> find_context_node(child, key)
      _text -> nil
    end)
  end

  defp context_event_params(%{"attrs" => attrs}) do
    attrs
    |> Enum.filter(fn {attribute, _value} -> String.starts_with?(attribute, "phx-value-") end)
    |> Map.new(fn {attribute, value} ->
      {String.replace_prefix(attribute, "phx-value-", ""), value}
    end)
  end

  describe "dashboard runtime context controls" do
    test "context selector can apply and clear a multi-transport runtime scope" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")

      alpha_transport =
        Transport.new(%{
          transport_id: "dashboard-context-alpha-transport",
          mission_id: mission.mission_id,
          display_name: "Alpha TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "alpha.ground.example",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_transport =
        Transport.new(%{
          transport_id: "dashboard-context-beta-transport",
          mission_id: mission.mission_id,
          display_name: "Alpha Backup TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "beta.ground.example",
            "port" => "5001",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-63"}
        })

      gamma_transport =
        Transport.new(%{
          transport_id: "dashboard-context-gamma-transport",
          mission_id: mission.mission_id,
          display_name: "Gamma TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "gamma.ground.example",
            "port" => "5002",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-43"}
        })

      assert {:ok, _transport} =
               TransportStore.persist_transport(
                 org.organization_id,
                 alpha_transport
               )

      assert {:ok, _transport} =
               TransportStore.persist_transport(org.organization_id, beta_transport)

      assert {:ok, _transport} =
               TransportStore.persist_transport(
                 org.organization_id,
                 gamma_transport
               )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Multi Transport Context Control",
          widgets: [value_tile("HK.counter", :context, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      render_hook(view, "context_search", %{"q" => "Alpha"})

      expected_scope_ids =
        "#{beta_transport.transport_id},#{alpha_transport.transport_id}"

      context_presentation = context_selector_presentation(view)

      batch_button =
        find_context_node(
          context_presentation,
          "data-dashboard-context-batch-result",
          "transport"
        )

      assert batch_button["attrs"] == %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "transport",
               "phx-value-scope-ids" => expected_scope_ids,
               "data-dashboard-context-batch-result" => "transport",
               "data-dashboard-context-batch-count" => "2",
               "data-dashboard-context-batch-ids" => expected_scope_ids,
               "class" =>
                 "mb-1 w-full rounded border border-primary/20 bg-primary/10 px-2 py-1 text-left text-sm hover:bg-primary/20"
             }

      refute String.contains?(
               batch_button["attrs"]["data-dashboard-context-batch-ids"],
               gamma_transport.transport_id
             )

      render_hook(
        view,
        batch_button["attrs"]["phx-click"],
        context_event_params(batch_button)
      )

      patched_path = assert_patch(view)
      assert patched_path =~ "scope_kind=transport"
      assert patched_path =~ "scope_ids=#{URI.encode_www_form(expected_scope_ids)}"
      refute patched_path =~ "scope_id="

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{beta_transport.transport_id}"][data-dashboard-scope-ids="#{expected_scope_ids}"])
             )

      selected_presentation = context_selector_presentation(view)
      selected = find_context_node(selected_presentation, "selected-context-label")

      assert selected["attrs"] == %{
               "id" => "dashboard-selected-context",
               "data-dashboard-selected-context-kind" => "transport",
               "data-dashboard-selected-context-id" => beta_transport.transport_id,
               "data-dashboard-selected-context-ids" => expected_scope_ids,
               "class" =>
                 "badge badge-primary badge-outline badge-sm mt-1 max-w-full truncate font-mono"
             }

      assert selected["children"] == ["2 transports"]

      clear_button =
        find_context_node(selected_presentation, "aria-label", "Clear context")

      assert clear_button["attrs"]["phx-click"] == "clear_context"
      render_hook(view, clear_button["attrs"]["phx-click"], %{})

      cleared_path = assert_patch(view)
      refute cleared_path =~ "scope_kind="
      refute cleared_path =~ "scope_id="
      refute cleared_path =~ "scope_ids="

      render_dashboard_async(view)

      refute context_selector_presentation(view)
             |> find_context_node("selected-context-label")

      stop_dashboard_view(view)
    end
  end
end
