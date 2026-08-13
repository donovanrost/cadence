defmodule Cadence.Extensions.Registry do
  @moduledoc "Tolerant structural registry of compiled first-party extension packages."

  alias Cadence.Extensions.{
    ApplicationContribution,
    CapabilityContribution,
    CatalogImporterContribution,
    ExtensionPackage,
    ProviderConnectorContribution,
    SourceAdapterContribution,
    TransportKindContribution,
    WidgetTypeContribution
  }

  @type fetch_error ::
          :unknown_extension_package
          | :unsupported_extension_package_version
          | :invalid_extension_package

  @spec all() :: [ExtensionPackage.t()]
  def all,
    do: [
      telemetry_package(),
      mission_assurance_package(),
      runtime_foundations_package(),
      cfdp_package(),
      tcp_transport_package(),
      ground_network_simulator_package(),
      dashboard_widgets_package(),
      dashboard_sources_package(),
      catalog_yaml_package()
    ]

  @spec available() :: [ExtensionPackage.t()]
  def available, do: Enum.filter(all(), &(ExtensionPackage.validate(&1) == :ok))

  @spec fetch(binary(), pos_integer() | :latest | nil) ::
          {:ok, ExtensionPackage.t()} | {:error, fetch_error()}
  def fetch(package_id, version \\ :latest)

  def fetch(package_id, version) when is_binary(package_id) do
    case Enum.find(all(), &(&1.package_id == package_id)) do
      %ExtensionPackage{} = package when version in [:latest, nil, package.version] ->
        case ExtensionPackage.validate(package) do
          :ok -> {:ok, package}
          {:error, :invalid_extension_package} -> {:error, :invalid_extension_package}
        end

      %ExtensionPackage{} ->
        {:error, :unsupported_extension_package_version}

      nil ->
        {:error, :unknown_extension_package}
    end
  end

  def fetch(_package_id, _version), do: {:error, :unknown_extension_package}

  defp telemetry_package do
    %ExtensionPackage{
      package_id: "cadence.telemetry-applications",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_application_contract: 1,
        cadence_surface_contract: 1,
        cadence_capability_abi: 1
      },
      contributions: [
        %ApplicationContribution{
          application_key: "telemetry_decom",
          application_version: 1
        },
        %ApplicationContribution{
          application_key: "derived_telemetry",
          application_version: 1
        },
        %CapabilityContribution{
          family_key: :definition_bound_telemetry,
          family_version: 1,
          kind: :semantic_handler
        }
      ]
    }
  end

  defp runtime_foundations_package do
    %ExtensionPackage{
      package_id: "cadence.runtime-foundations",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_capability_abi: 1},
      contributions: [
        %CapabilityContribution{
          family_key: :packet_counter,
          family_version: 1,
          kind: :managed_application
        },
        %CapabilityContribution{
          family_key: :heartbeat_monitor,
          family_version: 1,
          kind: :transport_extension
        },
        %CapabilityContribution{
          family_key: :uplink_gateway,
          family_version: 1,
          kind: :transport_extension
        }
      ]
    }
  end

  defp mission_assurance_package do
    %ExtensionPackage{
      package_id: "cadence.mission-assurance",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_application_contract: 1, cadence_surface_contract: 1},
      contributions: [
        %ApplicationContribution{
          application_key: "limits",
          application_version: 1
        }
      ]
    }
  end

  defp cfdp_package do
    %ExtensionPackage{
      package_id: "cadence.cfdp",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_application_contract: 1, cadence_capability_abi: 1},
      contributions: [
        %ApplicationContribution{application_key: "cfdp", application_version: 1},
        %CapabilityContribution{
          family_key: :cfdp_receive,
          family_version: 1,
          kind: :managed_application
        }
      ]
    }
  end

  defp tcp_transport_package do
    %ExtensionPackage{
      package_id: "cadence.tcp-transport",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_transport_kind_contract: 1,
        cadence_configuration_contract: 1
      },
      contributions: [
        %TransportKindContribution{
          transport_kind_key: "tcp_socket",
          transport_kind_version: 1
        }
      ]
    }
  end

  defp ground_network_simulator_package do
    %ExtensionPackage{
      package_id: "cadence.ground-network-simulator",
      version: 1,
      trust: :first_party,
      compatibility: %{
        cadence_provider_connector_contract: 1,
        cadence_configuration_contract: 1
      },
      contributions: [
        %ProviderConnectorContribution{
          provider_connector_key: "simulator",
          provider_connector_version: 1
        }
      ]
    }
  end

  defp dashboard_widgets_package do
    %ExtensionPackage{
      package_id: "cadence.dashboard-widgets",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_widget_type_contract: 1},
      contributions: [
        %WidgetTypeContribution{widget_type_id: "cadence.value_tile", widget_type_version: 1},
        %WidgetTypeContribution{widget_type_id: "cadence.time_series", widget_type_version: 1},
        %WidgetTypeContribution{widget_type_id: "cadence.status_matrix", widget_type_version: 1},
        %WidgetTypeContribution{widget_type_id: "cadence.data_table", widget_type_version: 1},
        %WidgetTypeContribution{widget_type_id: "cadence.state_timeline", widget_type_version: 1},
        %WidgetTypeContribution{widget_type_id: "cadence.event_timeline", widget_type_version: 1},
        %WidgetTypeContribution{
          widget_type_id: "cadence.constellation_health",
          widget_type_version: 1
        }
      ]
    }
  end

  defp dashboard_sources_package do
    %ExtensionPackage{
      package_id: "cadence.dashboard-sources",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_source_adapter_contract: 1},
      contributions: [
        %SourceAdapterContribution{logical_source: :telemetry, source_adapter_version: 1},
        %SourceAdapterContribution{logical_source: :limits, source_adapter_version: 1},
        %SourceAdapterContribution{
          logical_source: :operational_observables,
          source_adapter_version: 1
        },
        %SourceAdapterContribution{logical_source: :events, source_adapter_version: 1}
      ]
    }
  end

  defp catalog_yaml_package do
    %ExtensionPackage{
      package_id: "cadence.catalog-yaml",
      version: 1,
      trust: :first_party,
      compatibility: %{cadence_catalog_importer_contract: 1},
      contributions: [
        %CatalogImporterContribution{importer_key: "cadence_yaml", importer_version: 1},
        %CatalogImporterContribution{importer_key: "xtce_1_3", importer_version: 1}
      ]
    }
  end
end
