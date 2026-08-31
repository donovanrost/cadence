defmodule Cadence.Reads.ApplicationSurfacesTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    Registry,
    SurfaceDefinition,
    SurfaceQueryContribution,
    SurfaceQueryRequest
  }

  alias Cadence.Applications.SurfaceElements.{Diagnostic, Diagnostics}
  alias Cadence.Auth.Scope

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore,
    Transport,
    TransportRow,
    TransportStore
  }

  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore.PathTemplateRow
  alias Cadence.Contacts.ProfileStore
  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Extensions.Presentation.{ReferenceOption, ReferencePage}
  alias Cadence.Limits.Definition
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store
  alias Cadence.Listing.Page
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.{ApplicationReferences, ApplicationSurfaces}
  alias Cadence.Reads.Applications, as: ApplicationReads
  alias Cadence.Reads.ApplicationSurfaces.Comms, as: CommsSurface
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry
  alias Cadence.Repo
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.PacketDefinition

  import Ecto.Query

  @organization_id "org-application-surfaces"
  @mission_id "mission-application-surfaces"
  @secret_sentinel "R2_COMMS_PROVIDER_CONFIGURATION_SECRET_SENTINEL"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)
    {:ok, definition} = Registry.fetch_available("derived_telemetry")
    {:ok, surface} = Registry.fetch_default_surface(definition, :mission)

    %{scope: scope, host_context: host_context, definition: definition, surface: surface}
  end

  test "requires the exact active installation before loading a declared surface", context do
    assert {:error, :application_not_installed} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface
             )

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    assert {:ok, document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface
             )

    assert document.title == "Derived Telemetry"
    assert document.form.action_id == "save_definition"
    assert document.form.success_message == "Derived telemetry definition saved."
    assert document.table.id == "derived-telemetry-definitions"
    assert document.table.page == %Page{items: [], total_count: 0, page: 1, page_size: 20}
  end

  test "dispatches two contributed applications concurrently without cross-talk", context do
    contributions = [
      %SurfaceQueryContribution{
        application_key: "synthetic_alpha",
        application_version: 1,
        query_id: "synthetic.alpha.read",
        query_version: 1,
        provider: Cadence.TestSurfaceQueryProviders.Alpha
      },
      %SurfaceQueryContribution{
        application_key: "synthetic_beta",
        application_version: 1,
        query_id: "synthetic.beta.read",
        query_version: 1,
        provider: Cadence.TestSurfaceQueryProviders.Beta
      }
    ]

    providers = ProviderRegistry.providers(contributions)

    requests = [
      %SurfaceQueryRequest{
        application_key: "synthetic_alpha",
        application_version: 1,
        surface_id: "read",
        surface_version: 1,
        query_id: "synthetic.alpha.read",
        query_version: 1
      },
      %SurfaceQueryRequest{
        application_key: "synthetic_beta",
        application_version: 1,
        surface_id: "read",
        surface_version: 1,
        query_id: "synthetic.beta.read",
        query_version: 1
      }
    ]

    results =
      requests
      |> Task.async_stream(
        fn request ->
          ProviderRegistry.dispatch(context.scope, context.host_context, request, providers)
        end,
        max_concurrency: 2,
        ordered: true,
        timeout: 1_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert results == [
             {:ok, %{"provider" => "alpha", "application_key" => "synthetic_alpha"}},
             {:ok, %{"provider" => "beta", "application_key" => "synthetic_beta"}}
           ]
  end

  test "fails closed when contributed query providers exceed the registry cap" do
    contributions =
      Enum.map(1..65, fn index ->
        %SurfaceQueryContribution{
          application_key: "synthetic_#{index}",
          application_version: 1,
          query_id: "synthetic.read.#{index}",
          query_version: 1,
          provider: Cadence.TestSurfaceQueryProviders.Alpha
        }
      end)

    assert ProviderRegistry.providers(contributions) == %{}
  end

  test "validation keeps its repository query count fixed as spacecraft are added", context do
    persist_test_spacecraft("validation-query-count-a")
    persist_test_spacecraft("validation-query-count-b")

    for spacecraft_id <- ["validation-query-count-a", "validation-query-count-b"] do
      assert {:ok, _installation} =
               ApplicationInstallations.install(
                 context.scope,
                 HostContext.spacecraft(@mission_id, spacecraft_id),
                 "telemetry_decom"
               )
    end

    {first_result, first_query_count} =
      repo_query_count(fn -> CommsSurface.validation(context.scope, @mission_id) end)

    assert {:ok, _findings} = first_result

    persist_test_spacecraft("validation-query-count-c")

    {second_result, second_query_count} =
      repo_query_count(fn -> CommsSurface.validation(context.scope, @mission_id) end)

    assert {:ok, _findings} = second_result
    assert second_query_count == first_query_count
    assert second_query_count <= 24
  end

  test "spacecraft batch lookup performs one bounded repository query" do
    persist_test_spacecraft("batch-lookup-a")
    persist_test_spacecraft("batch-lookup-b")

    {result, query_count} =
      repo_query_count(fn ->
        Cadence.SpacecraftStore.fetch_spacecrafts(
          @organization_id,
          @mission_id,
          ["batch-lookup-a", "batch-lookup-b"]
        )
      end)

    assert {:ok, spacecrafts} = result
    assert Map.keys(spacecrafts) |> Enum.sort() == ["batch-lookup-a", "batch-lookup-b"]
    assert query_count == 1
  end

  test "spacecraft batch lookup rejects an oversized raw request before querying" do
    assert {:error, :batch_bounds_exceeded} =
             Cadence.SpacecraftStore.fetch_spacecrafts(
               @organization_id,
               @mission_id,
               Enum.map(1..101, &"oversized-#{&1}")
             )
  end

  test "loads all Comms v1 read surfaces as bounded trusted DTOs" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "comms")

    assert {:ok, comms_definition} = Registry.fetch_available("comms")

    transport =
      Transport.new(%{
        mission_id: @mission_id,
        transport_id: "transport-surface",
        display_name: "Secret-bearing transport",
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => @secret_sentinel,
          "port" => "5000",
          "framing_mode" => "raw",
          "frame_size" => "64",
          "reconnect_policy" => "always",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, persisted_transport} =
             TransportStore.persist_transport(@organization_id, transport)

    assert {:ok, provider_profile} =
             ProfileStore.fetch_provider_profile(
               @organization_id,
               @mission_id,
               persisted_transport.materialized_provider_profile_id
             )

    assert provider_profile.configuration["host"] == @secret_sentinel
    assert persisted_transport.configuration["host"] == @secret_sentinel

    Repo.update_all(
      from(row in TransportRow,
        where:
          row.organization_id == ^@organization_id and
            row.mission_id == ^@mission_id and
            row.transport_id == ^persisted_transport.transport_id and
            row.version == ^persisted_transport.version
      ),
      set: [
        provider_configuration_snapshot:
          JsonDocument.wrap_value(%{"secret_sentinel" => @secret_sentinel})
      ]
    )

    assert {:ok, stored_transport} =
             TransportStore.fetch_transport_version(
               @organization_id,
               @mission_id,
               persisted_transport.transport_id,
               persisted_transport.version
             )

    assert stored_transport.provider_configuration_snapshot["secret_sentinel"] ==
             @secret_sentinel

    for surface_id <- ~w(overview validation transports routing ground_stations) do
      assert {:ok, surface} = Registry.fetch_surface(comms_definition, :mission, surface_id)

      result =
        ApplicationSurfaces.load(
          scope,
          host_context,
          "comms",
          1,
          surface
        )

      assert match?({:ok, _}, result), "surface #{surface_id} returned #{inspect(result)}"
      assert {:ok, %{"navigation" => navigation, "data" => data}} = result
      assert_redacted_surface(result)

      assert navigation["fallback_href"] == comms_fallback_href(surface_id)
      assert is_map(data)
      assert Jason.decode!(Jason.encode!(data)) == data
    end

    assert {:ok, transports_surface} =
             Registry.fetch_surface(comms_definition, :mission, "transports")

    assert {:ok, %{"data" => %{"items" => [transport_row]}}} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               transports_surface
             )

    assert transport_row["id"] == persisted_transport.transport_id
    refute Map.has_key?(transport_row, "configuration")
    refute Map.has_key?(transport_row, "provider_configuration_snapshot")

    assert {:error, :unsupported_application_surface_query} =
             CommsSurface.load(
               scope,
               host_context,
               %SurfaceQueryRequest{
                 application_key: "comms",
                 application_version: 1,
                 surface_id: "overview",
                 surface_version: 1,
                 query_id: "cadence.comms.not-overview",
                 query_version: 1,
                 params: %{}
               }
             )

    assert {:error, :invalid_application_request} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               transports_surface,
               %{"unexpected" => "rejected"}
             )

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               transports_surface,
               %{"pageSize" => "1000000"}
             )

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               transports_surface,
               %{"page" => "10001"}
             )

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               transports_surface,
               %{"q" => String.duplicate("q", 241)}
             )

    oversized_params = Map.new(1..65, &{"param-#{&1}", "value"})

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               transports_surface,
               oversized_params
             )
  end

  test "fails closed for unsafe bounded payload terms" do
    assert :ok = CommsSurface.validate_bounded_payload(%{"count" => 1, "ratio" => 1.0})

    assert {:error, :application_surface_bounds_exceeded} =
             CommsSurface.validate_bounded_payload(9_007_199_254_740_992)

    assert {:error, :application_surface_bounds_exceeded} =
             CommsSurface.validate_bounded_payload(%{String.duplicate("a", 241) => "value"})

    assert {:error, :application_surface_bounds_exceeded} =
             CommsSurface.validate_bounded_payload(%{"unsupported" => self()})
  end

  test "rejects invalid detail IDs without fabricating a fallback segment" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)
    assert {:ok, _installation} = ApplicationInstallations.install(scope, host_context, "comms")
    assert {:ok, definition} = Registry.fetch_available("comms")
    assert {:ok, surface} = Registry.fetch_surface(definition, :mission, "transport")

    for invalid_id <- [
          "slash/id",
          "?query",
          "#fragment",
          "percent%20",
          "space id",
          "é",
          ".",
          "..",
          String.duplicate("a", 121)
        ] do
      result =
        ApplicationSurfaces.load(
          scope,
          host_context,
          "comms",
          1,
          surface,
          %{"transport_id" => invalid_id}
        )

      assert result == {:error, :invalid_application_request}
      refute inspect(result) =~ "/invalid"
    end
  end

  test "truncates multibyte display text at a valid byte boundary" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "comms")

    transport =
      Transport.new(%{
        mission_id: @mission_id,
        transport_id: "unicode-display",
        display_name: String.duplicate("界", 81),
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "127.0.0.1",
          "port" => "5000",
          "framing_mode" => "raw",
          "frame_size" => "64",
          "reconnect_policy" => "always",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, _persisted_transport} =
             TransportStore.persist_transport(@organization_id, transport)

    assert {:ok, comms_definition} = Registry.fetch_available("comms")
    assert {:ok, surface} = Registry.fetch_surface(comms_definition, :mission, "transports")

    assert {:ok, %{"data" => %{"items" => [row]}}} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               surface
             )

    assert byte_size(row["display_name"]) <= 240
    assert String.valid?(row["display_name"])
  end

  test "keeps missing reference findings reportable without emitting unsafe paths" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)
    assert {:ok, _installation} = ApplicationInstallations.install(scope, host_context, "comms")

    path_template =
      PathTemplate.new(%{
        mission_id: @mission_id,
        path_template_id: "missing-reference-template",
        path_id: "missing-reference-path",
        direction: :downlink,
        selection_role: :selected
      })

    assert {:ok, _persisted_path_template} =
             Cadence.Contacts.persist_path_template(@organization_id, path_template)

    Repo.update_all(
      from(row in PathTemplateRow,
        where:
          row.organization_id == ^@organization_id and
            row.mission_id == ^@mission_id and
            row.path_template_id == "missing-reference-template"
      ),
      set: [
        source_endpoint_ref: "missing-source-endpoint",
        provider_profile_ids: ["missing-provider-profile"],
        provider_profile_ref_documents: %{
          "items" => [%{"provider_profile_id" => "missing-provider-profile", "version" => 1}]
        },
        transport_profile_ids: ["missing-transport-profile"],
        transport_profile_ref_documents: %{
          "items" => [%{"transport_profile_id" => "missing-transport-profile", "version" => 1}]
        }
      ]
    )

    assert {:ok, findings} = CommsSurface.validation(scope, @mission_id)

    missing_reference =
      Enum.find(findings, fn finding ->
        finding.title == "missing-reference-path references a missing internal telemetry identity"
      end)

    refute Map.has_key?(missing_reference, :action_navigate)

    assert Enum.any?(
             findings,
             &(&1.title == "missing-reference-path references a missing provider")
           )

    missing_provider =
      Enum.find(findings, &(&1.title == "missing-reference-path references a missing provider"))

    refute Map.has_key?(missing_provider, :action_label)
    refute Map.has_key?(missing_provider, :action_navigate)

    assert Enum.any?(
             findings,
             &(&1.title == "missing-reference-path references a missing protocol behavior")
           )

    assert {:ok, definition} = Registry.fetch_available("comms")
    assert {:ok, surface} = Registry.fetch_surface(definition, :mission, "validation")

    assert {:ok, payload} =
             ApplicationSurfaces.load(scope, host_context, "comms", 1, surface)

    encoded = Jason.encode!(payload)
    assert encoded =~ "missing-reference-path references a missing internal telemetry identity"
    refute encoded =~ "/invalid"
  end

  test "restores the exact missing runtime identity finding for a spacecraft with SCID" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, HostContext.mission(@mission_id), "comms")

    spacecraft =
      Cadence.Spacecraft.new(%{
        mission_id: @mission_id,
        spacecraft_id: "runtime-identity-missing",
        display_name: "Runtime Identity Missing",
        scid: 42
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    assert {:ok, findings} = CommsSurface.validation(scope, @mission_id)

    assert Enum.any?(findings, fn finding ->
             finding.title == "Runtime Identity Missing has no internal telemetry identity" and
               finding.body ==
                 "Sync internal telemetry identity before execution can resolve this spacecraft." and
               finding.severity == :blocked and
               finding.action_label == "Edit identity" and
               finding.action_navigate ==
                 "/missions/#{@mission_id}/spacecraft/runtime-identity-missing/identity"
           end)
  end

  test "restores the exact missing selected downlink finding when a runtime identity exists" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, HostContext.mission(@mission_id), "comms")

    spacecraft =
      Cadence.Spacecraft.new(%{
        mission_id: @mission_id,
        spacecraft_id: "runtime-downlink-missing",
        display_name: "Runtime Downlink Missing",
        scid: 43
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "runtime-downlink-identity",
        mission_id: @mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Runtime downlink identity"
      })

    assert {:ok, _endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(@organization_id, endpoint)

    path_template =
      PathTemplate.new(%{
        mission_id: @mission_id,
        path_template_id: "available-downlink-runtime-path",
        path_id: "available-downlink-runtime-path",
        direction: :downlink,
        selection_role: :selected
      })

    assert {:ok, _path_template} =
             Cadence.Contacts.persist_path_template(@organization_id, path_template)

    Repo.update_all(
      from(row in PathTemplateRow,
        where:
          row.organization_id == ^@organization_id and
            row.mission_id == ^@mission_id and
            row.path_template_id == "available-downlink-runtime-path"
      ),
      set: [
        provider_profile_ids: ["available-provider-profile"],
        provider_profile_ref_documents: %{
          "items" => [%{"provider_profile_id" => "available-provider-profile", "version" => 1}]
        }
      ]
    )

    assert {:ok, findings} = CommsSurface.validation(scope, @mission_id)

    assert Enum.any?(findings, fn finding ->
             finding.title == "Runtime Downlink Missing has no selected downlink runtime artifact" and
               finding.body ==
                 "Routing Rules can materialize internal runtime artifacts for execution." and
               finding.severity == :attention and
               finding.action_label == "Review Routing" and
               finding.action_navigate ==
                 "/missions/#{@mission_id}/spacecraft/runtime-downlink-missing/routing"
           end)
  end

  test "loads valid detail surfaces and honors a routing rule's pinned transport version" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)
    assert {:ok, _installation} = ApplicationInstallations.install(scope, host_context, "comms")
    assert {:ok, comms_definition} = Registry.fetch_available("comms")

    spacecraft =
      Cadence.Spacecraft.new(%{
        mission_id: @mission_id,
        spacecraft_id: "surface-spacecraft",
        display_name: "Surface spacecraft",
        scid: 42
      })

    assert {:ok, persisted_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    transport =
      Transport.new(%{
        mission_id: @mission_id,
        transport_id: "versioned-transport",
        display_name: "Pinned transport v1",
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => @secret_sentinel,
          "port" => "5000",
          "framing_mode" => "raw",
          "frame_size" => "64",
          "reconnect_policy" => "always",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, persisted_transport} =
             TransportStore.persist_transport(@organization_id, transport)

    assert {:ok, _version_two} =
             TransportStore.version_transport(
               @organization_id,
               @mission_id,
               persisted_transport.transport_id,
               %{display_name: "Latest transport v2"}
             )

    assert {:ok, provider_profile} =
             ProfileStore.fetch_provider_profile(
               @organization_id,
               @mission_id,
               persisted_transport.materialized_provider_profile_id
             )

    assert provider_profile.configuration["host"] == @secret_sentinel
    assert persisted_transport.configuration["host"] == @secret_sentinel

    Repo.update_all(
      from(row in TransportRow,
        where:
          row.organization_id == ^@organization_id and
            row.mission_id == ^@mission_id and
            row.transport_id == ^persisted_transport.transport_id and
            row.version == ^persisted_transport.version
      ),
      set: [
        provider_configuration_snapshot:
          JsonDocument.wrap_value(%{"secret_sentinel" => @secret_sentinel})
      ]
    )

    routing_rule =
      RoutingRule.new(%{
        mission_id: @mission_id,
        spacecraft_id: persisted_spacecraft.spacecraft_id,
        routing_rule_id: "pinned-routing-rule",
        display_name: "Pinned routing rule",
        purpose_label: "Pinned detail regression",
        direction: :inbound,
        transport_id: persisted_transport.transport_id,
        transport_version: persisted_transport.version,
        role: :primary
      })

    assert {:ok, persisted_rule} =
             RoutingRuleStore.create_routing_rule(@organization_id, routing_rule)

    ground_station =
      GroundStation.new(%{
        mission_id: @mission_id,
        ground_station_id: "surface-ground-station",
        display_name: "Surface station",
        provider: "Surface provider",
        region: "Surface region"
      })

    assert {:ok, persisted_station} =
             GroundStationStore.persist_ground_station(@organization_id, ground_station)

    for {surface_id, params} <- [
          {"transport", %{"transport_id" => persisted_transport.transport_id}},
          {"routing_detail", %{"routing_rule_id" => persisted_rule.routing_rule_id}},
          {"ground_station", %{"ground_station_id" => persisted_station.ground_station_id}}
        ] do
      assert {:ok, surface} = Registry.fetch_surface(comms_definition, :mission, surface_id)

      assert {:ok, %{"navigation" => navigation, "data" => data}} =
               ApplicationSurfaces.load(
                 scope,
                 host_context,
                 "comms",
                 1,
                 surface,
                 params
               )

      assert is_map(data)
      assert navigation["fallback_href"] =~ "/missions/#{@mission_id}/comms/"
      assert_redacted_surface({:ok, %{"navigation" => navigation, "data" => data}})
    end

    assert {:ok, routing_surface} =
             Registry.fetch_surface(comms_definition, :mission, "routing_detail")

    assert {:ok, %{"data" => data}} =
             ApplicationSurfaces.load(
               scope,
               host_context,
               "comms",
               1,
               routing_surface,
               %{"routing_rule_id" => persisted_rule.routing_rule_id}
             )

    assert data["transport_version"] == 1
    assert data["transport_name"] == "Pinned transport v1"
    assert_redacted_surface({:ok, %{"data" => data}})
  end

  test "rejects undeclared surface contracts even when their query id is known", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    %SurfaceDefinition{} = surface = context.surface

    altered_surface = %SurfaceDefinition{surface | surface_id: "operator-supplied-surface"}

    assert {:error, :undeclared_application_surface} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               altered_surface
             )
  end

  test "returns bounded definition pages from declarative surface queries", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    for number <- 1..25 do
      suffix = number |> Integer.to_string() |> String.pad_leading(3, "0")

      definition =
        DerivedDefinition.new(%{
          mission_id: @mission_id,
          derived_definition_id: "paged-definition-#{suffix}",
          point_id: "DERIVED.paged_#{suffix}",
          point_name: "Paged #{suffix}",
          expression: "HK.source_#{suffix} * 2"
        })

      assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)
    end

    assert {:ok, first_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface
             )

    assert %Page{page: 1, page_size: 20, total_count: 25, items: first_rows} =
             first_document.table.page

    assert length(first_rows) == 20
    assert hd(first_rows).point == "DERIVED.paged_001"
    assert List.last(first_rows).point == "DERIVED.paged_020"

    assert {:ok, second_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface,
               %{"page" => "2"}
             )

    assert %Page{page: 2, page_size: 20, total_count: 25, items: second_rows} =
             second_document.table.page

    assert Enum.map(second_rows, & &1.point) ==
             Enum.map(21..25, fn number ->
               "DERIVED.paged_#{number |> Integer.to_string() |> String.pad_leading(3, "0")}"
             end)

    assert {:ok, clamped_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface,
               %{"page" => "999"}
             )

    assert clamped_document.table.page.page == 2
  end

  test "composes limits definitions and current severity into typed host elements", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "limits"
             )

    definition =
      Definition.new(%{
        mission_id: @mission_id,
        limit_definition_id: "limit-definition-surface",
        point_id: "HK.bus_voltage",
        limit_set_name: "FLIGHT",
        thresholds: %{"yellow_high" => 31.0, "red_high" => 32.5}
      })

    assert {:ok, ^definition} = Cadence.Limits.persist_limit_definition(definition)

    activate_point_catalog_fixture()

    derived_definition =
      DerivedDefinition.new(%{
        mission_id: @mission_id,
        derived_definition_id: "derived-definition-surface",
        point_id: "DERIVED.bus_power",
        point_name: "Bus power",
        expression: "HK.bus_voltage * 2"
      })

    assert {:ok, ^derived_definition} =
             Cadence.Governance.persist_derived_definition(derived_definition)

    now = DateTime.utc_now()

    event = %Event{
      limit_event_id: "limit-event-surface",
      mission_id: @mission_id,
      spacecraft_id: "spacecraft-surface",
      point_id: "HK.bus_voltage",
      point_name: "Bus voltage",
      source_sample_type: :telemetry_sample,
      sample_id: "sample-surface",
      limit_definition_id: definition.limit_definition_id,
      limit_definition_version: definition.version,
      limit_set_name: definition.limit_set_name,
      evaluated_value: 33.2,
      limit_state: :red_high,
      normalized_state: :red,
      violation: true,
      generation_time: now,
      receipt_time: now,
      provenance: %{}
    }

    assert {:ok, [_row]} = Store.persist_latest_states(Cadence.Repo, [event])

    assert {:ok, limits_definition} = Registry.fetch_available("limits")

    assert {:ok, definitions_surface} =
             Registry.fetch_surface(limits_definition, :mission, "manage")

    assert {:ok, document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               definitions_surface
             )

    assert document.title == "Limit definitions"
    assert document.form.action_id == "save_limit_definition"
    assert document.form.success_message == "Limit definition saved."

    assert [point_field | _remaining_fields] = document.form.fields
    assert point_field.field == :point_id
    assert point_field.type == :reference
    assert point_field.reference.provider_id == "cadence.telemetry.canonical_points"
    assert point_field.reference.version == 1
    assert point_field.reference.mode == :search
    assert point_field.reference.result_limit == 20

    assert %ReferencePage{query: "", more?: false} = point_field.reference_page

    assert point_field.reference_page.options == [
             %ReferenceOption{
               value: "DERIVED.bus_power",
               label: "DERIVED.bus_power",
               description: "Derived telemetry · Bus power"
             },
             %ReferenceOption{
               value: "HK.bus_voltage",
               label: "HK.bus_voltage",
               description: "Active telemetry · Unit: V"
             }
           ]

    assert document.table.id == "limit-definitions"

    assert %Page{page: 1, page_size: 20, total_count: 1, items: rows} =
             document.table.page

    assert [%{point: "HK.bus_voltage", version: "v1"}] = rows
    assert document.activity == nil

    assert {:ok, activity_surface} =
             Registry.fetch_surface(limits_definition, :mission, "activity")

    assert {:ok, activity_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               activity_surface
             )

    assert activity_document.title == "Current posture"
    assert activity_document.form == nil
    assert activity_document.table == nil

    assert %Diagnostics{
             id: "limit-current-diagnostics",
             title: "Current departures",
             total_count: 1,
             items: [
               %Diagnostic{
                 id: "red-departures",
                 code: "limits.current.red",
                 severity: :error,
                 value: "1 RED"
               }
             ]
           } = activity_document.diagnostics

    assert [activity_item] = activity_document.activity.items
    assert activity_item.title == "Bus voltage"
    assert activity_item.tone == :blocked
    assert activity_item.value == "33.2"

    assert {:ok, status} =
             ApplicationReads.load_status(
               context.scope,
               limits_definition,
               context.host_context
             )

    assert status.state == :red
    assert status.label == "Red limits"
    assert status.tone == :blocked
  end

  test "searches bounded reference pages through the authorized installed surface", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "limits"
             )

    for number <- 1..25 do
      suffix = number |> Integer.to_string() |> String.pad_leading(3, "0")

      definition =
        DerivedDefinition.new(%{
          mission_id: @mission_id,
          derived_definition_id: "search-definition-#{suffix}",
          point_id: "DERIVED.channel_#{suffix}",
          point_name: "Channel #{suffix}",
          expression: "HK.source_#{suffix} * 2"
        })

      assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)
    end

    assert {:ok, limits_definition} = Registry.fetch_available("limits")

    assert {:ok, surface} =
             Registry.fetch_surface(limits_definition, :mission, "manage")

    assert {:ok, document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface
             )

    assert [point_field | _remaining_fields] = document.form.fields

    assert %ReferencePage{query: "", more?: true, options: options} =
             point_field.reference_page

    assert length(options) == 20

    assert {:ok,
            %ReferencePage{
              query: "channel_025",
              more?: false,
              options: [%ReferenceOption{value: "DERIVED.channel_025"}]
            }} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "point_id",
               "channel_025"
             )

    assert {:ok, %ReferencePage{query: "missing", more?: false, options: []}} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "point_id",
               "missing"
             )

    assert {:error, :unknown_application_surface_reference} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "operator_field",
               "channel"
             )

    assert {:ok, _installation} =
             ApplicationInstallations.disable(
               context.scope,
               context.host_context,
               limits_definition.application_key
             )

    assert {:error, :application_installation_disabled} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "point_id",
               "channel"
             )
  end

  defp persist_test_spacecraft(spacecraft_id) do
    spacecraft =
      Cadence.Spacecraft.new(%{
        mission_id: @mission_id,
        spacecraft_id: spacecraft_id,
        display_name: spacecraft_id
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)
  end

  defp repo_query_count(fun) do
    test_pid = self()
    reference = make_ref()
    handler_id = {__MODULE__, reference}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, _metadata, {pid, query_reference} ->
          send(pid, {:repo_query, query_reference})
        end,
        {test_pid, reference}
      )

    try do
      result = fun.()
      {result, drain_repo_queries(reference)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_repo_queries(reference, count \\ 0) do
    receive do
      {:repo_query, ^reference} -> drain_repo_queries(reference, count + 1)
    after
      0 -> count
    end
  end

  defp activate_point_catalog_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: @mission_id,
        packet_definition_id: "hk-surface-packet",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            name: "bus_voltage",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint,
            engineering_unit: "V"
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: @mission_id,
        binding_set_id: "surface-point-catalog-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted} =
             Cadence.Governance.persist_binding_set(@organization_id, binding_set)

    content_sha256 = MissionRuntimeSpec.content_sha256(persisted)

    assert {:ok, _activation} =
             Cadence.Activations.record_binding_set_activation(
               @organization_id,
               @mission_id,
               persisted.binding_set_id,
               persisted.version,
               binding_set_content_sha256: content_sha256
             )
  end

  defp comms_fallback_href("overview"),
    do: "/missions/#{@mission_id}/comms"

  defp comms_fallback_href("validation"),
    do: "/missions/#{@mission_id}/comms/validation"

  defp comms_fallback_href("transports"),
    do: "/missions/#{@mission_id}/comms/transports"

  defp comms_fallback_href("routing"),
    do: "/missions/#{@mission_id}/comms/routing"

  defp comms_fallback_href("ground_stations"),
    do: "/missions/#{@mission_id}/comms/ground-stations"

  defp assert_redacted_surface({:ok, payload}) do
    encoded = Jason.encode!(payload)

    refute encoded =~ @secret_sentinel
    refute encoded =~ "\"configuration\":"
    refute encoded =~ "\"provider_configuration_snapshot\":"
    refute encoded =~ "\"secret\":"
  end
end
