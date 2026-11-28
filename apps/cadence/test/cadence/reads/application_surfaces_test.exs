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

  alias Cadence.Auth.Scope

  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Extensions.Presentation.{ReferenceOption, ReferencePage}
  alias Cadence.Limits.Definition
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store
  alias Cadence.Reads.{ApplicationReferences, ApplicationSurfaces}
  alias Cadence.Reads.Applications, as: ApplicationReads
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Telemetry.PacketDefinition

  @organization_id "org-application-surfaces"
  @mission_id "mission-application-surfaces"

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

    assert document["data"]["contract_version"] == 1
    assert document["data"]["context"]["mission_id"] == @mission_id
    assert document["data"]["definitions"]["items"] == []
    assert document["data"]["definitions"]["total_count"] == 0
    assert document["data"]["definitions"]["page_size"] == 25
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

  test "accepts the composed query registry at 128 contributions and fails closed at 129" do
    contributions =
      Enum.map(1..129, fn index ->
        %SurfaceQueryContribution{
          application_key: "synthetic_alpha",
          application_version: 1,
          query_id: "synthetic.alpha.#{index}",
          query_version: 1,
          provider: Cadence.TestSurfaceQueryProviders.Alpha
        }
      end)

    assert map_size(ProviderRegistry.providers(Enum.take(contributions, 128))) == 128
    assert ProviderRegistry.providers(contributions) == %{}
  end

  test "surface registry rejects duplicate query identities and invalid providers" do
    alpha = %SurfaceQueryContribution{
      application_key: "synthetic_alpha",
      application_version: 1,
      query_id: "synthetic.shared.read",
      query_version: 1,
      provider: Cadence.TestSurfaceQueryProviders.Alpha
    }

    beta_collision = %SurfaceQueryContribution{
      application_key: "synthetic_beta",
      application_version: 1,
      query_id: "synthetic.shared.read",
      query_version: 1,
      provider: Cadence.TestSurfaceQueryProviders.Beta
    }

    assert ProviderRegistry.providers([alpha, beta_collision]) == %{}
    assert ProviderRegistry.providers([alpha, alpha]) == %{}

    assert ProviderRegistry.providers([%{alpha | provider: String}]) == %{}

    mismatched_providers = %{
      {"synthetic_beta", "synthetic.shared.read"} => Cadence.TestSurfaceQueryProviders.Alpha
    }

    assert ProviderRegistry.dispatch(
             %Scope{},
             HostContext.mission("synthetic-mission"),
             %SurfaceQueryRequest{
               application_key: "synthetic_beta",
               application_version: 1,
               surface_id: "read",
               surface_version: 1,
               query_id: "synthetic.shared.read",
               query_version: 1
             },
             mismatched_providers
           ) == {:error, :invalid_application_surface_provider_registry}
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

  test "returns bounded definition pages from the module-owned surface query", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    for number <- 1..30 do
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

    assert %{"page" => 1, "page_size" => 25, "total_count" => 30, "items" => first_rows} =
             first_document["data"]["definitions"]

    assert length(first_rows) == 25
    assert hd(first_rows)["point_id"] == "DERIVED.paged_001"
    assert List.last(first_rows)["point_id"] == "DERIVED.paged_025"

    assert {:ok, second_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface,
               %{"page" => "2"}
             )

    assert %{"page" => 2, "page_size" => 25, "total_count" => 30, "items" => second_rows} =
             second_document["data"]["definitions"]

    assert Enum.map(second_rows, & &1["point_id"]) ==
             Enum.map(26..30, fn number ->
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

    assert clamped_document["data"]["definitions"]["page"] == 2
  end

  test "composes semantic limits definitions, source choices and current severity", context do
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

    assert document["data"]["definitions"]["total_count"] == 1
    assert document["data"]["definitions"]["page_size"] == 25

    assert [%{"point_id" => "HK.bus_voltage", "version" => 1}] =
             document["data"]["definitions"]["items"]

    assert document["data"]["points"]["items"] == [
             %{"id" => "DERIVED.bus_power", "label" => "Bus power", "kind" => "derived"},
             %{"id" => "HK.bus_voltage", "label" => "HK.bus_voltage", "kind" => "telemetry"}
           ]

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

    assert activity_document["data"]["counts"]["red"] == 1
    assert activity_document["data"]["states"]["total_count"] == 1
    assert [state] = activity_document["data"]["states"]["items"]
    assert state["point_name"] == "Bus voltage"
    assert state["severity"] == "red"
    assert state["value"] == "33.2"
    assert state["definition_version"] == 1
    assert state["sample_id"] == "sample-surface"

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

    assert document["data"]["points"]["total_count"] == 25
    assert length(document["data"]["points"]["items"]) == 25

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
end
