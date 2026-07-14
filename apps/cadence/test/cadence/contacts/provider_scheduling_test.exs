defmodule Cadence.Contacts.ProviderSchedulingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderProfile, ProviderScheduling}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-scheduling-#{suffix}"
    mission_id = "mission-provider-scheduling-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    spacecraft = persist_spacecraft(organization_id, mission_id, suffix, "primary")

    endpoint =
      persist_endpoint(
        organization_id,
        mission_id,
        spacecraft.spacecraft_id,
        suffix,
        "primary",
        "SIM-001"
      )

    provider = persist_provider(organization_id, mission_id, suffix, "ready", valid_config())

    path_template =
      persist_path(
        organization_id,
        mission_id,
        endpoint.source_endpoint_id,
        provider,
        suffix,
        "ready"
      )

    _assignment =
      persist_assignment(
        organization_id,
        mission_id,
        spacecraft,
        endpoint,
        path_template,
        provider,
        suffix,
        "ready"
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft: spacecraft,
      endpoint: endpoint,
      provider: provider,
      path_template: path_template,
      suffix: suffix
    }
  end

  test "returns a provider-ready route and validates opportunity search", context do
    assert {:ok, %{routes: [route], findings: []}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    assert route.provider_spacecraft_ref == "SIM-001"
    assert route.provider_profile_id == context.provider.provider_profile_id
    assert route.path_template_version == context.path_template.version

    starts_at = DateTime.utc_now() |> DateTime.add(120) |> DateTime.truncate(:second)
    ends_at = DateTime.add(starts_at, 3_600)

    opportunity = %{
      "id" => "opportunity-alpha",
      "spacecraft_id" => "SIM-001",
      "ground_station_id" => "station-alpha",
      "antenna_id" => "antenna-alpha",
      "starts_at" => starts_at |> DateTime.add(300) |> DateTime.to_iso8601(),
      "ends_at" => starts_at |> DateTime.add(900) |> DateTime.to_iso8601()
    }

    assert {:ok, %{route: searched_route, opportunities: [result]}} =
             ProviderScheduling.search_opportunities(
               context.organization_id,
               context.mission_id,
               route.route_key,
               %{
                 "spacecraft_id" => context.spacecraft.spacecraft_id,
                 "starts_at" => DateTime.to_iso8601(starts_at),
                 "ends_at" => DateTime.to_iso8601(ends_at)
               },
               client: FakeProviderClient,
               search_response: {:ok, %{"data" => [opportunity]}}
             )

    assert searched_route.route_key == route.route_key
    assert result["id"] == "opportunity-alpha"
    assert result["route_key"] == route.route_key
  end

  test "reports missing source endpoint and provider spacecraft reference separately", context do
    spacecraft_without_endpoint =
      persist_spacecraft(
        context.organization_id,
        context.mission_id,
        context.suffix,
        "no-endpoint"
      )

    assert {:ok, %{routes: [], findings: [%{code: :missing_source_endpoint}]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               spacecraft_without_endpoint.spacecraft_id
             )

    spacecraft_without_ref =
      persist_spacecraft(
        context.organization_id,
        context.mission_id,
        context.suffix,
        "no-ref"
      )

    _endpoint =
      persist_endpoint(
        context.organization_id,
        context.mission_id,
        spacecraft_without_ref.spacecraft_id,
        context.suffix,
        "no-ref",
        nil
      )

    assert {:ok, %{routes: [], findings: findings}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               spacecraft_without_ref.spacecraft_id
             )

    assert Enum.map(findings, & &1.code) == [:missing_provider_spacecraft_reference]
  end

  test "reports missing downlink path", context do
    spacecraft =
      persist_spacecraft(
        context.organization_id,
        context.mission_id,
        context.suffix,
        "no-path"
      )

    _endpoint =
      persist_endpoint(
        context.organization_id,
        context.mission_id,
        spacecraft.spacecraft_id,
        context.suffix,
        "no-path",
        "SIM-NO-PATH"
      )

    assert {:ok, %{routes: [], findings: findings}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               spacecraft.spacecraft_id
             )

    assert Enum.map(findings, & &1.code) == [:missing_downlink_route]
  end

  test "reports scheduling client, run scope, and data-plane blockers", context do
    variants = [
      {"no-client", Map.delete(valid_config(), "scheduling"), :missing_scheduling_client},
      {"no-run", put_in(valid_config(), ["scheduling", "run_id"], nil),
       :missing_provider_run_scope},
      {"no-delivery", put_in(valid_config(), ["scheduling", "delivery_host"], nil),
       :missing_data_plane_configuration},
      {"bad-port", Map.put(valid_config(), "port", 0), :missing_data_plane_configuration},
      {"bad-framing", put_in(valid_config(), ["framing", "mode"], "raw"),
       :missing_data_plane_configuration}
    ]

    Enum.each(variants, fn {name, configuration, expected_code} ->
      spacecraft =
        persist_spacecraft(
          context.organization_id,
          context.mission_id,
          context.suffix,
          name
        )

      endpoint =
        persist_endpoint(
          context.organization_id,
          context.mission_id,
          spacecraft.spacecraft_id,
          context.suffix,
          name,
          "SIM-#{name}"
        )

      provider =
        persist_provider(
          context.organization_id,
          context.mission_id,
          context.suffix,
          name,
          configuration
        )

      path =
        persist_path(
          context.organization_id,
          context.mission_id,
          endpoint.source_endpoint_id,
          provider,
          context.suffix,
          name
        )

      _assignment =
        persist_assignment(
          context.organization_id,
          context.mission_id,
          spacecraft,
          endpoint,
          path,
          provider,
          context.suffix,
          name
        )

      assert {:ok, %{routes: [], findings: findings}} =
               ProviderScheduling.list_ready_downlink_routes(
                 context.organization_id,
                 context.mission_id,
                 spacecraft.spacecraft_id
               )

      assert Enum.any?(findings, &(&1.code == expected_code))
    end)
  end

  test "route keys cannot cross organization or mission scope", context do
    assert {:ok, %{routes: [route]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    assert {:error, :spacecraft_not_found} =
             ProviderScheduling.resolve_ready_downlink_route(
               "another-organization",
               context.mission_id,
               context.spacecraft.spacecraft_id,
               route.route_key
             )

    assert {:error, :spacecraft_not_found} =
             ProviderScheduling.resolve_ready_downlink_route(
               context.organization_id,
               "another-mission",
               context.spacecraft.spacecraft_id,
               route.route_key
             )
  end

  test "rejects invalid windows and mismatched provider opportunities", context do
    assert {:ok, %{routes: [route]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    starts_at = DateTime.utc_now() |> DateTime.add(120) |> DateTime.truncate(:second)
    ends_at = DateTime.add(starts_at, 3_600)

    window = %{
      "spacecraft_id" => context.spacecraft.spacecraft_id,
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at)
    }

    assert {:error, :invalid_opportunity_window} =
             ProviderScheduling.search_opportunities(
               context.organization_id,
               context.mission_id,
               route.route_key,
               %{window | "ends_at" => window["starts_at"]},
               client: FakeProviderClient
             )

    mismatched = %{
      "id" => "opportunity-wrong-spacecraft",
      "spacecraft_id" => "ANOTHER-SPACECRAFT",
      "starts_at" => starts_at |> DateTime.add(60) |> DateTime.to_iso8601(),
      "ends_at" => starts_at |> DateTime.add(120) |> DateTime.to_iso8601()
    }

    assert {:error, {:invalid_provider_opportunity, "opportunity-wrong-spacecraft"}} =
             ProviderScheduling.search_opportunities(
               context.organization_id,
               context.mission_id,
               route.route_key,
               window,
               client: FakeProviderClient,
               search_response: {:ok, %{"data" => [mismatched]}}
             )
  end

  defp persist_spacecraft(organization_id, mission_id, suffix, name) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-#{suffix}-#{name}",
        mission_id: mission_id,
        display_name: "Spacecraft #{name}"
      })

    {:ok, spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)
    spacecraft
  end

  defp persist_endpoint(organization_id, mission_id, spacecraft_id, suffix, name, source_ref) do
    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-#{suffix}-#{name}",
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        source_ref: source_ref,
        display_name: "Source #{name}"
      })

    {:ok, endpoint} = Cadence.persist_source_endpoint(organization_id, endpoint)
    endpoint
  end

  defp persist_provider(organization_id, mission_id, suffix, name, configuration) do
    provider =
      ProviderProfile.new(%{
        provider_profile_id: "provider-#{suffix}-#{name}",
        mission_id: mission_id,
        adapter_key: :tcp_socket,
        configuration: configuration,
        metadata: %{"display_name" => "Provider #{name}"}
      })

    {:ok, provider} = Cadence.persist_provider_profile(organization_id, provider)
    provider
  end

  defp persist_path(organization_id, mission_id, source_endpoint_id, provider, suffix, name) do
    path =
      PathTemplate.new(%{
        path_template_id: "path-#{suffix}-#{name}",
        mission_id: mission_id,
        path_id: "downlink-#{suffix}-#{name}",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_id,
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ],
        metadata: %{"display_name" => "Downlink #{name}"}
      })

    {:ok, path} = Cadence.persist_path_template(organization_id, path)
    path
  end

  defp persist_assignment(
         organization_id,
         mission_id,
         spacecraft,
         endpoint,
         path,
         provider,
         suffix,
         name
       ) do
    assignment =
      LinkAssignment.new(%{
        link_assignment_id: "assignment-#{suffix}-#{name}",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: endpoint.source_endpoint_id,
        path_template_id: path.path_template_id,
        path_template_version: path.version,
        direction: :downlink,
        selection_role: :selected,
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ]
      })

    {:ok, assignment} = Cadence.persist_link_assignment(organization_id, assignment)
    assignment
  end

  defp valid_config do
    %{
      "adapter" => "tcp_socket",
      "mode" => "listen",
      "direction" => "downlink",
      "host" => "0.0.0.0",
      "port" => 4_100,
      "fixed_message_bytes" => 64,
      "framing" => %{"mode" => "fixed_size", "fixed_message_bytes" => 64},
      "scheduling" => %{
        "client" => "simulator_http",
        "base_url" => "http://simulator.test",
        "delivery_host" => "cadence.test",
        "run_id" => "run-alpha"
      }
    }
  end
end
