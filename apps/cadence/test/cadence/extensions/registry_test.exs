defmodule Cadence.Extensions.RegistryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.{ActionDispatcher, ApplicationPreflight}
  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Capabilities.{DefinitionRegistry, Descriptor}
  alias Cadence.Catalog.Registry, as: CatalogImporterRegistry
  alias Cadence.Comms.TransportKind
  alias Cadence.Contacts.ProviderClients.Registry, as: ProviderConnectorRegistry
  alias Cadence.Dashboards.WidgetRegistry
  alias Cadence.DataSources.AdapterRegistry
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications, as: ApplicationReads
  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.ReferenceResolver

  alias Cadence.Extensions.{
    ApplicationContribution,
    CapabilityContribution,
    CatalogImporterContribution,
    ExtensionPackage,
    PackageDependency,
    ProviderConnectorContribution,
    Registry,
    SourceAdapterContribution,
    TransportKindContribution,
    WidgetTypeContribution
  }

  test "resolves versioned first-party packages without conflating contribution versions" do
    assert Enum.all?(Registry.all(), &(ExtensionPackage.validate(&1) == :ok))
    assert Enum.all?(Registry.all(), &(ExtensionCatalog.validate_package(&1) == :ok))

    assert {:ok, %ExtensionPackage{} = package} = ExtensionCatalog.fetch("cadence.cfdp")
    assert package.version == 1
    assert package.trust == :first_party

    assert %ApplicationContribution{
             application_key: "cfdp",
             application_version: 1
           } in package.contributions

    assert %CapabilityContribution{
             family_key: :cfdp_receive,
             family_version: 1,
             kind: :managed_application
           } in package.contributions

    assert {:error, :unsupported_extension_package_version} =
             ExtensionCatalog.fetch("cadence.cfdp", 2)

    assert {:error, :unknown_extension_package} = ExtensionCatalog.fetch("mission-uploaded")
  end

  test "every typed contribution resolves through its owning domain registry" do
    for contribution <- ExtensionCatalog.application_contributions() do
      assert {:ok, definition} =
               ApplicationRegistry.fetch(
                 contribution.application_key,
                 contribution.application_version
               )

      assert definition.application_key == contribution.application_key
      assert definition.version == contribution.application_version
    end

    definitions = DefinitionRegistry.default()

    for contribution <- ExtensionCatalog.capability_contributions() do
      assert {:ok, %Descriptor{} = descriptor} =
               DefinitionRegistry.fetch_descriptor(definitions, contribution.family_key)

      assert descriptor.family_key == contribution.family_key
      assert descriptor.version == contribution.family_version
      assert descriptor.kind == contribution.kind
    end

    for contribution <- ExtensionCatalog.catalog_importer_contributions() do
      assert {:ok, %{descriptor: descriptor}} =
               CatalogImporterRegistry.fetch_builtin_importer(
                 contribution.importer_key,
                 contribution.importer_version
               )

      assert descriptor.importer_key == contribution.importer_key
      assert descriptor.version == contribution.importer_version
      assert descriptor.trust == :first_party
    end

    for contribution <- ExtensionCatalog.transport_kind_contributions() do
      assert {:ok, definition} =
               TransportKind.resolve_form_value(
                 contribution.transport_kind_key,
                 contribution.transport_kind_version
               )

      assert definition.form_value == contribution.transport_kind_key
      assert definition.version == contribution.transport_kind_version
    end

    for contribution <- ExtensionCatalog.provider_connector_contributions() do
      assert {:ok, definition} =
               ProviderConnectorRegistry.fetch_definition(
                 contribution.provider_connector_key,
                 contribution.provider_connector_version
               )

      assert definition.form_value == contribution.provider_connector_key
      assert definition.version == contribution.provider_connector_version
    end

    for contribution <- ExtensionCatalog.widget_type_contributions() do
      assert {:ok, widget_type} =
               WidgetRegistry.fetch_type(
                 contribution.widget_type_id,
                 contribution.widget_type_version
               )

      assert widget_type.widget_type_id == contribution.widget_type_id
      assert widget_type.version == contribution.widget_type_version
    end

    for contribution <- ExtensionCatalog.source_adapter_contributions() do
      assert {:ok, definition} =
               AdapterRegistry.fetch_definition(
                 contribution.logical_source,
                 contribution.source_adapter_version
               )

      assert definition.logical_source == contribution.logical_source
      assert definition.version == contribution.source_adapter_version
    end
  end

  test "transport kinds and provider connectors are package-backed discovery" do
    assert {:ok, transport_package} = ExtensionCatalog.fetch("cadence.tcp-transport")

    assert transport_package.contributions == [
             %TransportKindContribution{
               transport_kind_key: "tcp_socket",
               transport_kind_version: 1
             }
           ]

    assert {:ok, %{form_value: "tcp_socket", version: 1}} =
             ExtensionCatalog.fetch_transport_kind("tcp_socket", 1)

    assert Enum.map(ExtensionCatalog.transport_kinds(), &{&1.form_value, &1.version}) ==
             Enum.map(TransportKind.available(), &{&1.form_value, &1.version})

    assert {:error, :unsupported_transport_kind_contribution_version} =
             ExtensionCatalog.fetch_transport_kind("tcp_socket", 2)

    assert {:error, :unknown_transport_kind_contribution} =
             ExtensionCatalog.fetch_transport_kind("invented")

    assert {:ok, provider_package} =
             ExtensionCatalog.fetch("cadence.ground-network-simulator")

    assert provider_package.contributions == [
             %ProviderConnectorContribution{
               provider_connector_key: "simulator",
               provider_connector_version: 1
             }
           ]

    assert {:ok, %{form_value: "simulator", version: 1}} =
             ExtensionCatalog.fetch_provider_connector("simulator", 1)

    assert Enum.map(ExtensionCatalog.provider_connectors(), &{&1.form_value, &1.version}) ==
             Enum.map(ProviderConnectorRegistry.available(), &{&1.form_value, &1.version})

    assert {:error, :unsupported_provider_connector_contribution_version} =
             ExtensionCatalog.fetch_provider_connector("simulator", 2)

    assert {:error, :unknown_provider_connector_contribution} =
             ExtensionCatalog.fetch_provider_connector("invented")
  end

  test "dashboard widget types and built-in source adapters are package-backed discovery" do
    assert {:ok, widget_package} = ExtensionCatalog.fetch("cadence.dashboard-widgets")

    assert Enum.all?(widget_package.contributions, &match?(%WidgetTypeContribution{}, &1))

    assert {:ok, %{widget_type_id: "cadence.time_series", version: 1}} =
             ExtensionCatalog.fetch_widget_type("cadence.time_series", 1)

    assert MapSet.new(ExtensionCatalog.widget_types(), &{&1.widget_type_id, &1.version}) ==
             MapSet.new(WidgetRegistry.list_types(), &{&1.widget_type_id, &1.version})

    assert {:error, :unsupported_widget_type_contribution_version} =
             ExtensionCatalog.fetch_widget_type("cadence.time_series", 2)

    assert {:error, :unknown_widget_type_contribution} =
             ExtensionCatalog.fetch_widget_type("partner.unknown")

    assert {:ok, source_package} = ExtensionCatalog.fetch("cadence.dashboard-sources")

    assert Enum.all?(source_package.contributions, &match?(%SourceAdapterContribution{}, &1))

    assert {:ok, %{logical_source: :telemetry, version: 1}} =
             ExtensionCatalog.fetch_source_adapter(:telemetry, 1)

    assert Enum.map(ExtensionCatalog.source_adapters(), &{&1.logical_source, &1.version}) ==
             Enum.map(AdapterRegistry.list_definitions(), &{&1.logical_source, &1.version})

    assert {:error, :unsupported_source_adapter_contribution_version} =
             ExtensionCatalog.fetch_source_adapter(:telemetry, 2)

    assert {:error, :unknown_source_adapter_contribution} =
             ExtensionCatalog.fetch_source_adapter(:invented)
  end

  test "catalog importers are exact package-backed built-ins" do
    assert {:ok, package} = ExtensionCatalog.fetch("cadence.catalog-yaml")

    assert package.contributions == [
             %CatalogImporterContribution{importer_key: "cadence_yaml", importer_version: 1}
           ]

    assert {:ok, %{descriptor: %{importer_key: "cadence_yaml", version: 1}}} =
             ExtensionCatalog.fetch_catalog_importer("cadence_yaml", 1)

    assert Enum.map(ExtensionCatalog.catalog_importers(), fn registration ->
             {registration.descriptor.importer_key, registration.descriptor.version}
           end) == [{"cadence_yaml", 1}]

    assert {:ok, %{descriptor: %{importer_key: "cadence_yaml"}}} =
             ExtensionCatalog.detect_catalog_importer("mission.yaml", "application/yaml")

    assert {:error, :no_matching_importer} =
             ExtensionCatalog.detect_catalog_importer("mission.xml", "application/xml")

    assert {:error, :unsupported_catalog_importer_contribution_version} =
             ExtensionCatalog.fetch_catalog_importer("cadence_yaml", 2)

    assert {:error, :unknown_catalog_importer_contribution} =
             ExtensionCatalog.fetch_catalog_importer("configured-only")
  end

  test "package contributions are authoritative for application discovery" do
    assert :ok = ExtensionCatalog.validate()

    assert ExtensionCatalog.inventory() == %{
             packages: 9,
             applications: 4,
             available_applications: 3,
             capabilities: 5,
             transport_kinds: 1,
             provider_connectors: 1,
             widget_types: 7,
             source_adapters: 4,
             catalog_importers: 1
           }

    assert Enum.map(ExtensionCatalog.applications_for_scope(:spacecraft), & &1.application_key) ==
             ["telemetry_decom"]

    assert Enum.map(ExtensionCatalog.applications_for_scope(:mission), & &1.application_key) ==
             ["derived_telemetry", "limits", "cfdp"]

    assert Enum.map(
             ExtensionCatalog.available_applications_for_scope(:mission),
             & &1.application_key
           ) == ["derived_telemetry", "limits"]

    assert {:ok, %{application_key: "derived_telemetry", version: 1}} =
             ExtensionCatalog.fetch_available_application("derived_telemetry", 1)

    assert {:ok, %{application_key: "cfdp", availability: :roadmap}} =
             ExtensionCatalog.fetch_application("cfdp")

    assert {:error, :application_unavailable} =
             ExtensionCatalog.fetch_available_application("cfdp")

    assert {:error, :unsupported_application_contribution_version} =
             ExtensionCatalog.fetch_application("derived_telemetry", 99)

    assert {:error, :unknown_application_contribution} =
             ExtensionCatalog.fetch_application("not_registered")

    contributed_versions =
      ExtensionCatalog.application_contributions()
      |> MapSet.new(&{&1.application_key, &1.application_version})

    registered_versions =
      ApplicationRegistry.all()
      |> MapSet.new(&{&1.application_key, &1.version})

    assert contributed_versions == registered_versions
  end

  test "complete catalog validation rejects hidden invalid and duplicate packages" do
    packages = Registry.all()
    assert :ok = ExtensionCatalog.validate_packages(packages)

    assert {:error, :invalid_extension_catalog} = ExtensionCatalog.validate_packages([])

    assert {:error, :invalid_extension_catalog} =
             ExtensionCatalog.validate_packages([hd(packages) | packages])

    invalid_package = %ExtensionPackage{
      package_id: "cadence.invalid-compiled-package",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_application_contract: 1},
      contributions: [
        %ApplicationContribution{
          application_key: "missing-compiled-application",
          application_version: 1
        }
      ]
    }

    assert {:error, :invalid_extension_catalog} =
             ExtensionCatalog.validate_packages(packages ++ [invalid_package])
  end

  test "every declared host contract has one valid plane-owned provider binding" do
    definitions = ApplicationRegistry.all()

    assert :ok = ActionDispatcher.validate_providers()
    assert :ok = ApplicationPreflight.validate_providers()
    assert :ok = ApplicationReads.validate_providers()
    assert :ok = ApplicationSurfaces.validate_providers()
    assert :ok = ReferenceResolver.validate_providers()

    assert {:error, :invalid_application_action_provider_registry} =
             ActionDispatcher.validate_providers(definitions, %{})

    assert {:error, :invalid_application_preflight_provider_registry} =
             ApplicationPreflight.validate_providers(definitions, %{})

    assert {:error, :invalid_application_status_provider_registry} =
             ApplicationReads.validate_providers(definitions, %{})

    assert {:error, :invalid_application_surface_provider_registry} =
             ApplicationSurfaces.validate_providers(definitions, %{})

    assert {:error, :invalid_application_reference_provider_registry} =
             ReferenceResolver.validate_providers(definitions, %{})
  end

  test "rejects unresolved contribution versions, kinds, and surface contracts" do
    invalid_application_version = %ExtensionPackage{
      package_id: "cadence.invalid-application-version",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_application_contract: 1,
        cadence_surface_contract: 1
      },
      contributions: [
        %ApplicationContribution{
          application_key: "derived_telemetry",
          application_version: 99
        }
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_application_version)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_application_version)

    missing_surface_contract = %ExtensionPackage{
      invalid_application_version
      | package_id: "cadence.missing-surface-contract",
        compatibility: %{cadence_application_contract: 1},
        contributions: [
          %ApplicationContribution{
            application_key: "derived_telemetry",
            application_version: 1
          }
        ]
    }

    assert :ok = ExtensionPackage.validate(missing_surface_contract)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(missing_surface_contract)

    invalid_capability = %ExtensionPackage{
      package_id: "cadence.invalid-capability",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_capability_abi: 1},
      contributions: [
        %CapabilityContribution{
          family_key: :cfdp_receive,
          family_version: 2,
          kind: :projection
        }
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_capability)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_capability)

    invalid_capability_kind = %ExtensionPackage{
      invalid_capability
      | package_id: "cadence.invalid-capability-kind",
        contributions: [
          %CapabilityContribution{
            family_key: :cfdp_receive,
            family_version: 1,
            kind: :projection
          }
        ]
    }

    assert :ok = ExtensionPackage.validate(invalid_capability_kind)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_capability_kind)

    invalid_transport_kind = %ExtensionPackage{
      package_id: "cadence.invalid-transport-kind",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_transport_kind_contract: 1,
        cadence_configuration_contract: 1
      },
      contributions: [
        %TransportKindContribution{
          transport_kind_key: "tcp_socket",
          transport_kind_version: 99
        }
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_transport_kind)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_transport_kind)

    invalid_provider_connector = %ExtensionPackage{
      package_id: "cadence.invalid-provider-connector",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_provider_connector_contract: 1,
        cadence_configuration_contract: 1
      },
      contributions: [
        %ProviderConnectorContribution{
          provider_connector_key: "simulator",
          provider_connector_version: 99
        }
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_provider_connector)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_provider_connector)

    invalid_widget_type = %ExtensionPackage{
      package_id: "cadence.invalid-widget-type",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_widget_type_contract: 1},
      contributions: [
        %WidgetTypeContribution{
          widget_type_id: "cadence.time_series",
          widget_type_version: 99
        }
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_widget_type)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_widget_type)

    invalid_source_adapter = %ExtensionPackage{
      package_id: "cadence.invalid-source-adapter",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_source_adapter_contract: 1},
      contributions: [
        %SourceAdapterContribution{
          logical_source: :telemetry,
          source_adapter_version: 99
        }
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_source_adapter)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_source_adapter)

    invalid_catalog_importer = %ExtensionPackage{
      package_id: "cadence.invalid-catalog-importer",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_catalog_importer_contract: 1},
      contributions: [
        %CatalogImporterContribution{importer_key: "cadence_yaml", importer_version: 99}
      ]
    }

    assert :ok = ExtensionPackage.validate(invalid_catalog_importer)

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(invalid_catalog_importer)
  end

  test "mission assurance is an application-only package over the existing limits domain" do
    assert {:ok, %ExtensionPackage{} = package} =
             ExtensionCatalog.fetch("cadence.mission-assurance")

    assert package.contributions == [
             %ApplicationContribution{
               application_key: "limits",
               application_version: 1
             }
           ]
  end

  test "resolves required and optional package dependencies without recursive registry calls" do
    package = %ExtensionPackage{
      package_id: "cadence.dependency-proof",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_application_contract: 1},
      contributions: [
        %ApplicationContribution{application_key: "cfdp", application_version: 1}
      ]
    }

    assert :ok = ExtensionCatalog.validate_package(package)

    assert :ok =
             ExtensionCatalog.validate_package(%ExtensionPackage{
               package
               | dependencies: [
                   %PackageDependency{package_id: "not-installed", required: false}
                 ]
             })

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(%ExtensionPackage{
               package
               | dependencies: [
                   %PackageDependency{package_id: "not-installed", required: true}
                 ]
             })

    assert {:error, :invalid_extension_package} =
             ExtensionCatalog.validate_package(%ExtensionPackage{
               package
               | dependencies: [
                   %PackageDependency{
                     package_id: "cadence.cfdp",
                     minimum_version: 2
                   }
                 ]
             })
  end
end
