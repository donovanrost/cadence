defmodule Cadence.Applications.CommsApplicationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.{
    ActionProviderRegistry,
    ApplicationDefinition,
    Comms,
    CatalogRegistry,
    LegacyCommsOverview,
    Registry,
    ReleaseContribution,
    ReleaseRegistry
  }

  test "publishes the complete mission-scoped Comms surface contract" do
    assert Comms.identity() == %{
             application_key: "comms",
             application_version: 1,
             package_id: "cadence.comms",
             package_version: 1,
             surface_version: 1,
             release_id: "comms-v1",
             remote_name: "cadence_comms",
             manifest_path: "/assets/application-host/comms/mf-manifest.json",
             exposed_module: "./Application"
           }

    assert ApplicationDefinition.validate(Comms.definition()) == :ok

    assert Comms.surface_ids() == [
             "overview",
             "validation",
             "transports",
             "transport",
             "routing",
             "routing_detail",
             "ground_stations",
             "ground_station",
             "provider_list",
             "provider_new",
             "provider_show",
             "transport_new",
             "routing_new",
             "ground_station_new",
             "ground_station_edit"
           ]

    assert Enum.map(Comms.surface_query_contributions(), & &1.query_id) == [
             "cadence.comms.overview",
             "cadence.comms.validation",
             "cadence.comms.transports",
             "cadence.comms.transport",
             "cadence.comms.routing",
             "cadence.comms.routing_detail",
             "cadence.comms.ground_stations",
             "cadence.comms.ground_station",
             "cadence.comms.provider_list",
             "cadence.comms.provider_new",
             "cadence.comms.provider_show",
             "cadence.comms.transport_new",
             "cadence.comms.routing_new",
             "cadence.comms.ground_station_new",
             "cadence.comms.ground_station_edit"
           ]

    assert Enum.map(Comms.definition().surfaces, &surface_contract/1) == [
             %{
               surface_id: "overview",
               version: 1,
               purpose: :overview,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "Overview",
                 order: 10,
                 fallback_path: "/comms",
                 fallback_parent_path: nil
               },
               data_contract: %{query_id: "cadence.comms.overview", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.overview"}
             },
             %{
               surface_id: "validation",
               version: 1,
               purpose: :activity,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "Validation",
                 order: 20,
                 fallback_path: "/comms/validation",
                 fallback_parent_path: nil
               },
               data_contract: %{query_id: "cadence.comms.validation", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.validation"}
             },
             %{
               surface_id: "transports",
               version: 1,
               purpose: :collection,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "Transports",
                 order: 30,
                 fallback_path: "/comms/transports",
                 fallback_parent_path: nil
               },
               data_contract: %{query_id: "cadence.comms.transports", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.transports"}
             },
             %{
               surface_id: "transport",
               version: 1,
               purpose: :subject_detail,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: %{
                 schema_id: "cadence.comms.transport.subject",
                 version: 1
               },
               navigation: %{
                 label: "Transport",
                 order: 40,
                 fallback_path: "/comms/transports/:subject",
                 fallback_parent_path: "/comms/transports"
               },
               data_contract: %{query_id: "cadence.comms.transport", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.transport"}
             },
             %{
               surface_id: "routing",
               version: 1,
               purpose: :collection,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "Routing",
                 order: 50,
                 fallback_path: "/comms/routing",
                 fallback_parent_path: nil
               },
               data_contract: %{query_id: "cadence.comms.routing", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.routing"}
             },
             %{
               surface_id: "routing_detail",
               version: 1,
               purpose: :subject_detail,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: %{
                 schema_id: "cadence.comms.routing_rule.subject",
                 version: 1
               },
               navigation: %{
                 label: "Routing Rule",
                 order: 60,
                 fallback_path: "/comms/routing/:subject",
                 fallback_parent_path: "/comms/routing"
               },
               data_contract: %{query_id: "cadence.comms.routing_detail", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.routing_detail"}
             },
             %{
               surface_id: "ground_stations",
               version: 1,
               purpose: :collection,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "Ground Stations",
                 order: 70,
                 fallback_path: "/comms/ground-stations",
                 fallback_parent_path: nil
               },
               data_contract: %{query_id: "cadence.comms.ground_stations", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.ground_stations"}
             },
             %{
               surface_id: "ground_station",
               version: 1,
               purpose: :subject_detail,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: %{
                 schema_id: "cadence.comms.ground_station.subject",
                 version: 1
               },
               navigation: %{
                 label: "Ground Station",
                 order: 80,
                 fallback_path: "/comms/ground-stations/:subject",
                 fallback_parent_path: "/comms/ground-stations"
               },
               data_contract: %{query_id: "cadence.comms.ground_station", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.ground_station"}
             },
             %{
               surface_id: "provider_list",
               version: 1,
               purpose: :collection,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "Providers",
                 order: 90,
                 fallback_path: "/comms/providers",
                 fallback_parent_path: nil
               },
               data_contract: %{query_id: "cadence.comms.provider_list", version: 1},
               actions: [],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.provider_list"}
             },
             %{
               surface_id: "provider_new",
               version: 1,
               purpose: :configuration,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "New Provider",
                 order: 100,
                 fallback_path: "/comms/providers/new",
                 fallback_parent_path: "/comms/providers"
               },
               data_contract: %{query_id: "cadence.comms.provider_new", version: 1},
               actions: ["create_provider"],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.provider_new"}
             },
             %{
               surface_id: "provider_show",
               version: 1,
               purpose: :subject_detail,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: %{
                 schema_id: "cadence.comms.provider.subject",
                 version: 1
               },
               navigation: %{
                 label: "Provider",
                 order: 110,
                 fallback_path: "/comms/providers/:subject",
                 fallback_parent_path: "/comms/providers"
               },
               data_contract: %{query_id: "cadence.comms.provider_show", version: 1},
               actions: ["validate_provider", "sync_provider", "archive_provider"],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.provider_show"}
             },
             %{
               surface_id: "transport_new",
               version: 1,
               purpose: :configuration,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "New Transport",
                 order: 120,
                 fallback_path: "/comms/transports/new",
                 fallback_parent_path: "/comms/transports"
               },
               data_contract: %{query_id: "cadence.comms.transport_new", version: 1},
               actions: ["validate", "save"],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.transport_new"}
             },
             %{
               surface_id: "routing_new",
               version: 1,
               purpose: :configuration,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "New Routing Rule",
                 order: 130,
                 fallback_path: "/comms/routing/new",
                 fallback_parent_path: "/comms/routing"
               },
               data_contract: %{query_id: "cadence.comms.routing_new", version: 1},
               actions: ["validate", "save"],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.routing_new"}
             },
             %{
               surface_id: "ground_station_new",
               version: 1,
               purpose: :configuration,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: nil,
               navigation: %{
                 label: "New Ground Station",
                 order: 140,
                 fallback_path: "/comms/ground-stations/new",
                 fallback_parent_path: "/comms/ground-stations"
               },
               data_contract: %{query_id: "cadence.comms.ground_station_new", version: 1},
               actions: ["validate", "save"],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.ground_station_new"}
             },
             %{
               surface_id: "ground_station_edit",
               version: 1,
               purpose: :configuration,
               scope: :mission,
               placement: :application_workspace,
               subject_contract: %{
                 schema_id: "cadence.comms.ground_station.subject",
                 version: 1
               },
               navigation: %{
                 label: "Edit Ground Station",
                 order: 150,
                 fallback_path: "/comms/ground-stations/:subject/edit",
                 fallback_parent_path: "/comms/ground-stations"
               },
               data_contract: %{query_id: "cadence.comms.ground_station_edit", version: 1},
               actions: ["validate", "save"],
               refresh: :static,
               renderer: {:trusted, "cadence.comms.ground_station_edit"}
             }
           ]
  end

  test "contributes one immutable module-federation release coordinate per surface" do
    contributions = Comms.release_contributions()

    assert length(contributions) == 15
    assert Enum.all?(contributions, &(ReleaseContribution.validate(&1) == :ok))

    assert Enum.uniq_by(contributions, &ReleaseContribution.release/1) == [
             %ReleaseContribution{
               application_key: "comms",
               application_version: 1,
               surface_id: "overview",
               surface_version: 1,
               federation: :module_federation,
               release_id: "comms-v1",
               remote_name: "cadence_comms",
               manifest_path: "/assets/application-host/comms/mf-manifest.json",
               exposed_module: "./Application"
             }
           ]
  end

  test "leaves the legacy overview identity available as a separate contract" do
    legacy = LegacyCommsOverview.identity()

    assert legacy.application_key == "comms_overview"
    assert legacy.package_id == "cadence.comms_overview"
    assert legacy.query_id == "cadence.comms.overview"
    assert legacy.release_id == "comms-overview-v1"
    assert legacy.remote_name == "cadence_comms"
    assert legacy.manifest_path == "/assets/application-host/comms/mf-manifest.json"
    assert legacy.exposed_module == "./LegacyApplication"
  end

  test "admits canonical and retained legacy catalog and release contributions" do
    assert {:ok, %{package_id: "cadence.comms"}} = CatalogRegistry.fetch("comms")

    assert {:ok, %{package_id: "cadence.comms_overview"}} =
             CatalogRegistry.fetch("comms_overview")

    assert {:ok, canonical_release} = ReleaseRegistry.fetch("comms", 1, "overview", 1)

    assert canonical_release == %ReleaseContribution{
             application_key: "comms",
             application_version: 1,
             surface_id: "overview",
             surface_version: 1,
             federation: :module_federation,
             release_id: "comms-v1",
             remote_name: "cadence_comms",
             manifest_path: "/assets/application-host/comms/mf-manifest.json",
             exposed_module: "./Application"
           }

    assert {:ok, legacy_release} = ReleaseRegistry.fetch("comms_overview", 1, "overview", 1)

    assert legacy_release == %ReleaseContribution{
             application_key: "comms_overview",
             application_version: 1,
             surface_id: "overview",
             surface_version: 1,
             federation: :module_federation,
             release_id: "comms-overview-v1",
             remote_name: "cadence_comms",
             manifest_path: "/assets/application-host/comms/mf-manifest.json",
             exposed_module: "./LegacyApplication"
           }
  end

  test "registers provider query contributions with subject and form contracts" do
    contributions = Comms.surface_query_contributions()

    assert contributions
           |> Enum.filter(
             &(&1.query_id in [
                 "cadence.comms.provider_list",
                 "cadence.comms.provider_new",
                 "cadence.comms.provider_show"
               ])
           )
           |> Enum.map(&{&1.query_id, &1.provider}) == [
             {"cadence.comms.provider_list", Cadence.Reads.ApplicationSurfaces.CommsProviders},
             {"cadence.comms.provider_new", Cadence.Reads.ApplicationSurfaces.CommsProviders},
             {"cadence.comms.provider_show", Cadence.Reads.ApplicationSurfaces.CommsProviders}
           ]

    assert {:ok, provider_show} =
             Registry.fetch_surface(Comms.definition(), :mission, "provider_show")

    assert provider_show.subject_contract == %{
             schema_id: "cadence.comms.provider.subject",
             version: 1
           }
  end

  test "registers the Comms provider action adapter for declared provider actions" do
    providers = ActionProviderRegistry.providers([Comms])

    assert {:ok, Cadence.Applications.Comms.ActionProvider} =
             ActionProviderRegistry.fetch("comms", providers)

    assert Enum.map(Comms.definition().actions, & &1.action_id) == [
             "create_provider",
             "validate_provider",
             "sync_provider",
             "archive_provider",
             "validate",
             "save"
           ]
  end

  test "documents shared form action isolation composition requirement" do
    assert Enum.map(Comms.definition().actions, &{&1.action_id, &1.effect})
           |> Enum.take(-2) == [{"validate", :none}, {"save", :durable}]

    assert "transport_new" in Enum.map(Comms.definition().surfaces, & &1.surface_id)
    assert "ground_station_edit" in Enum.map(Comms.definition().surfaces, & &1.surface_id)

    # The provider reads ActionRequest.surface_id when the host composes it.
    # Cross-surface action isolation requires that shared host composition.
  end

  defp surface_contract(surface) do
    Map.take(surface, [
      :surface_id,
      :version,
      :purpose,
      :scope,
      :placement,
      :subject_contract,
      :navigation,
      :data_contract,
      :actions,
      :refresh,
      :renderer
    ])
  end
end
