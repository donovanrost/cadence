defmodule Cadence.Extensions.ExtensionPackage do
  @moduledoc """
  Compile-time distribution envelope for a versioned set of typed first-party
  contributions.

  Package identity and version are distinct from every contributed domain
  identifier and version.
  """

  alias Cadence.Extensions.{
    ApplicationContribution,
    CapabilityContribution,
    CatalogImporterContribution,
    PackageDependency,
    ProviderConnectorContribution,
    SourceAdapterContribution,
    TransportKindContribution,
    WidgetTypeContribution
  }

  @type contribution ::
          ApplicationContribution.t()
          | CapabilityContribution.t()
          | CatalogImporterContribution.t()
          | TransportKindContribution.t()
          | ProviderConnectorContribution.t()
          | WidgetTypeContribution.t()
          | SourceAdapterContribution.t()

  @type t :: %__MODULE__{
          package_id: binary(),
          version: pos_integer(),
          trust: :first_party,
          compatibility: %{optional(compatibility_contract()) => pos_integer()},
          dependencies: [PackageDependency.t()],
          contributions: [contribution()]
        }

  @enforce_keys [:package_id, :version, :trust, :contributions]
  defstruct [
    :package_id,
    :version,
    :trust,
    compatibility: %{},
    dependencies: [],
    contributions: []
  ]

  @type compatibility_contract ::
          :cadence_application_contract
          | :cadence_surface_contract
          | :cadence_capability_abi
          | :cadence_configuration_contract
          | :cadence_transport_kind_contract
          | :cadence_provider_connector_contract
          | :cadence_widget_type_contract
          | :cadence_source_adapter_contract
          | :cadence_catalog_importer_contract

  @supported_compatibility %{
    cadence_application_contract: 1,
    cadence_surface_contract: 1,
    cadence_capability_abi: 1,
    cadence_configuration_contract: 1,
    cadence_transport_kind_contract: 1,
    cadence_provider_connector_contract: 1,
    cadence_widget_type_contract: 1,
    cadence_source_adapter_contract: 1,
    cadence_catalog_importer_contract: 1
  }

  @max_dependencies 16
  @max_contributions 64

  @spec validate(t()) :: :ok | {:error, :invalid_extension_package}
  def validate(%__MODULE__{} = package) do
    with true <- valid_text?(package.package_id),
         true <- is_integer(package.version) and package.version > 0,
         true <- package.trust == :first_party,
         true <- valid_compatibility?(package.compatibility),
         true <- valid_dependencies?(package.dependencies, package.package_id),
         true <- valid_contributions?(package.contributions),
         true <- declares_required_contracts?(package) do
      :ok
    else
      _invalid -> {:error, :invalid_extension_package}
    end
  end

  def validate(_package), do: {:error, :invalid_extension_package}

  @spec supported_compatibility() :: %{compatibility_contract() => pos_integer()}
  def supported_compatibility, do: @supported_compatibility

  defp valid_compatibility?(compatibility) when is_map(compatibility) do
    compatibility != %{} and
      Enum.all?(compatibility, fn {contract, version} ->
        Map.get(@supported_compatibility, contract) == version
      end)
  end

  defp valid_compatibility?(_compatibility), do: false

  defp valid_dependencies?(dependencies, package_id) when is_list(dependencies) do
    dependency_ids = Enum.map(dependencies, &dependency_id/1)

    length(dependencies) <= @max_dependencies and
      Enum.all?(dependencies, &(PackageDependency.validate(&1) == :ok)) and
      Enum.all?(dependency_ids, &(&1 != package_id)) and
      length(Enum.uniq(dependency_ids)) == length(dependency_ids)
  end

  defp valid_dependencies?(_dependencies, _package_id), do: false

  defp dependency_id(%PackageDependency{package_id: package_id}), do: package_id
  defp dependency_id(_dependency), do: nil

  defp valid_contributions?(contributions) when is_list(contributions) do
    contribution_ids = Enum.map(contributions, &contribution_id/1)

    contributions != [] and length(contributions) <= @max_contributions and
      Enum.all?(contributions, &valid_contribution?/1) and
      length(Enum.uniq(contribution_ids)) == length(contribution_ids)
  end

  defp valid_contributions?(_contributions), do: false

  defp valid_contribution?(%ApplicationContribution{} = contribution),
    do: ApplicationContribution.validate(contribution) == :ok

  defp valid_contribution?(%CapabilityContribution{} = contribution),
    do: CapabilityContribution.validate(contribution) == :ok

  defp valid_contribution?(%CatalogImporterContribution{} = contribution),
    do: CatalogImporterContribution.validate(contribution) == :ok

  defp valid_contribution?(%TransportKindContribution{} = contribution),
    do: TransportKindContribution.validate(contribution) == :ok

  defp valid_contribution?(%ProviderConnectorContribution{} = contribution),
    do: ProviderConnectorContribution.validate(contribution) == :ok

  defp valid_contribution?(%WidgetTypeContribution{} = contribution),
    do: WidgetTypeContribution.validate(contribution) == :ok

  defp valid_contribution?(%SourceAdapterContribution{} = contribution),
    do: SourceAdapterContribution.validate(contribution) == :ok

  defp valid_contribution?(_contribution), do: false

  defp contribution_id(%ApplicationContribution{application_key: application_key}),
    do: {:application, application_key}

  defp contribution_id(%CapabilityContribution{family_key: family_key}),
    do: {:capability, family_key}

  defp contribution_id(%CatalogImporterContribution{importer_key: importer_key}),
    do: {:catalog_importer, importer_key}

  defp contribution_id(%TransportKindContribution{transport_kind_key: transport_kind_key}),
    do: {:transport_kind, transport_kind_key}

  defp contribution_id(%ProviderConnectorContribution{
         provider_connector_key: provider_connector_key
       }),
       do: {:provider_connector, provider_connector_key}

  defp contribution_id(%WidgetTypeContribution{widget_type_id: widget_type_id}),
    do: {:widget_type, widget_type_id}

  defp contribution_id(%SourceAdapterContribution{logical_source: logical_source}),
    do: {:source_adapter, logical_source}

  defp contribution_id(_contribution), do: nil

  defp declares_required_contracts?(%__MODULE__{} = package) do
    package.contributions
    |> Enum.flat_map(&required_contracts/1)
    |> Enum.uniq()
    |> Enum.all?(&Map.has_key?(package.compatibility, &1))
  end

  defp required_contracts(%ApplicationContribution{}), do: [:cadence_application_contract]
  defp required_contracts(%CapabilityContribution{}), do: [:cadence_capability_abi]

  defp required_contracts(%CatalogImporterContribution{}),
    do: [:cadence_catalog_importer_contract]

  defp required_contracts(%TransportKindContribution{}),
    do: [:cadence_transport_kind_contract, :cadence_configuration_contract]

  defp required_contracts(%ProviderConnectorContribution{}),
    do: [:cadence_provider_connector_contract, :cadence_configuration_contract]

  defp required_contracts(%WidgetTypeContribution{}), do: [:cadence_widget_type_contract]
  defp required_contracts(%SourceAdapterContribution{}), do: [:cadence_source_adapter_contract]

  defp required_contracts(_contribution), do: []

  defp valid_text?(value), do: is_binary(value) and value != ""
end
