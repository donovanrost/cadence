defmodule Cadence.ExtensionCatalog do
  @moduledoc """
  Composition boundary that resolves structurally valid extension packages
  through each contribution's owning domain registry.
  """

  alias Cadence.Applications.ApplicationDefinition
  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Capabilities.{DefinitionRegistry, Descriptor}
  alias Cadence.Catalog.ImporterDescriptor
  alias Cadence.Catalog.Registry, as: CatalogImporterRegistry
  alias Cadence.Comms.TransportKind
  alias Cadence.Comms.TransportKind.Definition, as: TransportKindDefinition
  alias Cadence.Contacts.ProviderClients.Definition, as: ProviderConnectorDefinition
  alias Cadence.Contacts.ProviderClients.Registry, as: ProviderConnectorRegistry

  alias Cadence.Dashboards.{
    DefaultSourceAdapters,
    SourceAdapterDefinition,
    WidgetRegistry,
    WidgetType
  }

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

  @type fetch_error :: Registry.fetch_error() | :invalid_extension_package
  @type application_fetch_error ::
          ApplicationRegistry.fetch_error()
          | :application_unavailable
          | :unknown_application_contribution
          | :unsupported_application_contribution_version

  @type transport_kind_fetch_error ::
          TransportKind.fetch_error()
          | :unknown_transport_kind_contribution
          | :unsupported_transport_kind_contribution_version

  @type provider_connector_fetch_error ::
          ProviderConnectorRegistry.definition_fetch_error()
          | :unknown_provider_connector_contribution
          | :unsupported_provider_connector_contribution_version

  @type widget_type_fetch_error ::
          WidgetRegistry.fetch_error()
          | :unknown_widget_type_contribution
          | :unsupported_widget_type_contribution_version

  @type source_adapter_fetch_error ::
          DefaultSourceAdapters.definition_fetch_error()
          | :unknown_source_adapter_contribution
          | :unsupported_source_adapter_contribution_version

  @type catalog_importer_fetch_error ::
          CatalogImporterRegistry.fetch_error()
          | :unknown_catalog_importer_contribution
          | :unsupported_catalog_importer_contribution_version

  @type inventory :: %{
          packages: non_neg_integer(),
          applications: non_neg_integer(),
          available_applications: non_neg_integer(),
          capabilities: non_neg_integer(),
          transport_kinds: non_neg_integer(),
          provider_connectors: non_neg_integer(),
          widget_types: non_neg_integer(),
          source_adapters: non_neg_integer(),
          catalog_importers: non_neg_integer()
        }

  @spec available() :: [ExtensionPackage.t()]
  def available do
    packages = resolved_packages()
    if unique_contribution_ownership?(packages), do: packages, else: []
  end

  @spec fetch(binary(), pos_integer() | :latest | nil) ::
          {:ok, ExtensionPackage.t()} | {:error, fetch_error()}
  def fetch(package_id, version \\ :latest) do
    with {:ok, %ExtensionPackage{} = package} <- Registry.fetch(package_id, version),
         :ok <- validate_package(package) do
      {:ok, package}
    end
  end

  @spec validate_package(ExtensionPackage.t()) :: :ok | {:error, :invalid_extension_package}
  def validate_package(%ExtensionPackage{} = package) do
    with :ok <- ExtensionPackage.validate(package),
         :ok <- validate_dependencies(package),
         :ok <- validate_contributions(package) do
      :ok
    else
      _invalid -> {:error, :invalid_extension_package}
    end
  end

  def validate_package(_package), do: {:error, :invalid_extension_package}

  @spec validate() :: :ok | {:error, :invalid_extension_catalog}
  def validate, do: validate_packages(Registry.all())

  @doc "Validates a complete compiled package catalog without hiding invalid entries."
  @spec validate_packages([ExtensionPackage.t()]) ::
          :ok | {:error, :invalid_extension_catalog}
  def validate_packages(packages) when is_list(packages) and packages != [] do
    with true <- Enum.all?(packages, &(validate_package(&1) == :ok)),
         true <- unique_package_ownership?(packages),
         true <- unique_contribution_ownership?(packages) do
      :ok
    else
      _invalid -> {:error, :invalid_extension_catalog}
    end
  end

  def validate_packages(_packages), do: {:error, :invalid_extension_catalog}

  @doc "Returns stable counts for the validated, composed extension catalog."
  @spec inventory() :: inventory()
  def inventory do
    definitions = application_contributions()

    %{
      packages: length(available()),
      applications: length(definitions),
      available_applications:
        Enum.count(definitions, fn contribution ->
          match?(
            {:ok, %ApplicationDefinition{availability: :available}},
            ApplicationRegistry.fetch(
              contribution.application_key,
              contribution.application_version
            )
          )
        end),
      capabilities: length(capability_contributions()),
      transport_kinds: length(transport_kind_contributions()),
      provider_connectors: length(provider_connector_contributions()),
      widget_types: length(widget_type_contributions()),
      source_adapters: length(source_adapter_contributions()),
      catalog_importers: length(catalog_importer_contributions())
    }
  end

  @spec application_contributions() :: [ApplicationContribution.t()]
  def application_contributions, do: contributions_of_type(ApplicationContribution)

  @spec capability_contributions() :: [CapabilityContribution.t()]
  def capability_contributions, do: contributions_of_type(CapabilityContribution)

  @spec catalog_importer_contributions() :: [CatalogImporterContribution.t()]
  def catalog_importer_contributions, do: contributions_of_type(CatalogImporterContribution)

  @spec transport_kind_contributions() :: [TransportKindContribution.t()]
  def transport_kind_contributions, do: contributions_of_type(TransportKindContribution)

  @spec provider_connector_contributions() :: [ProviderConnectorContribution.t()]
  def provider_connector_contributions, do: contributions_of_type(ProviderConnectorContribution)

  @spec widget_type_contributions() :: [WidgetTypeContribution.t()]
  def widget_type_contributions, do: contributions_of_type(WidgetTypeContribution)

  @spec source_adapter_contributions() :: [SourceAdapterContribution.t()]
  def source_adapter_contributions, do: contributions_of_type(SourceAdapterContribution)

  @spec fetch_application(binary(), pos_integer() | :latest | nil) ::
          {:ok, ApplicationDefinition.t()}
          | {:error, application_fetch_error()}
  def fetch_application(application_key, version \\ :latest)

  def fetch_application(application_key, version) when is_binary(application_key) do
    with {:ok, contribution} <- fetch_application_contribution(application_key, version) do
      ApplicationRegistry.fetch(
        contribution.application_key,
        contribution.application_version
      )
    end
  end

  def fetch_application(_application_key, _version),
    do: {:error, :unknown_application_contribution}

  @spec fetch_available_application(binary(), pos_integer() | :latest | nil) ::
          {:ok, ApplicationDefinition.t()}
          | {:error, application_fetch_error()}
  def fetch_available_application(application_key, version \\ :latest) do
    with {:ok, definition} <- fetch_application(application_key, version),
         true <- ApplicationDefinition.available?(definition) do
      {:ok, definition}
    else
      false -> {:error, :application_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec applications_for_scope(ApplicationDefinition.scope()) :: [ApplicationDefinition.t()]
  def applications_for_scope(scope) do
    application_contributions()
    |> Enum.flat_map(fn contribution ->
      case ApplicationRegistry.fetch(
             contribution.application_key,
             contribution.application_version
           ) do
        {:ok, definition} -> [definition]
        _unavailable_or_unsupported -> []
      end
    end)
    |> Enum.filter(&(scope in &1.installable_scopes))
  end

  @spec available_applications_for_scope(ApplicationDefinition.scope()) ::
          [ApplicationDefinition.t()]
  def available_applications_for_scope(scope) do
    scope
    |> applications_for_scope()
    |> Enum.filter(&ApplicationDefinition.available?/1)
  end

  @spec transport_kinds() :: [TransportKindDefinition.t()]
  def transport_kinds do
    Enum.flat_map(transport_kind_contributions(), fn contribution ->
      case TransportKind.resolve_form_value(
             contribution.transport_kind_key,
             contribution.transport_kind_version
           ) do
        {:ok, definition} -> [definition]
        _invalid_or_unsupported -> []
      end
    end)
  end

  @spec fetch_transport_kind(binary(), pos_integer() | :latest | nil) ::
          {:ok, TransportKindDefinition.t()} | {:error, transport_kind_fetch_error()}
  def fetch_transport_kind(transport_kind_key, version \\ :latest)

  def fetch_transport_kind(transport_kind_key, version) when is_binary(transport_kind_key) do
    with {:ok, contribution} <-
           fetch_transport_kind_contribution(transport_kind_key, version) do
      TransportKind.resolve_form_value(
        contribution.transport_kind_key,
        contribution.transport_kind_version
      )
    end
  end

  def fetch_transport_kind(_transport_kind_key, _version),
    do: {:error, :unknown_transport_kind_contribution}

  @spec provider_connectors() :: [ProviderConnectorDefinition.t()]
  def provider_connectors do
    Enum.flat_map(provider_connector_contributions(), fn contribution ->
      case ProviderConnectorRegistry.fetch_definition(
             contribution.provider_connector_key,
             contribution.provider_connector_version
           ) do
        {:ok, definition} -> [definition]
        _invalid_or_unsupported -> []
      end
    end)
  end

  @spec fetch_provider_connector(binary(), pos_integer() | :latest | nil) ::
          {:ok, ProviderConnectorDefinition.t()} | {:error, provider_connector_fetch_error()}
  def fetch_provider_connector(provider_connector_key, version \\ :latest)

  def fetch_provider_connector(provider_connector_key, version)
      when is_binary(provider_connector_key) do
    with {:ok, contribution} <-
           fetch_provider_connector_contribution(provider_connector_key, version) do
      ProviderConnectorRegistry.fetch_definition(
        contribution.provider_connector_key,
        contribution.provider_connector_version
      )
    end
  end

  def fetch_provider_connector(_provider_connector_key, _version),
    do: {:error, :unknown_provider_connector_contribution}

  @spec catalog_importers() :: [CatalogImporterRegistry.importer_registration()]
  def catalog_importers do
    Enum.flat_map(catalog_importer_contributions(), fn contribution ->
      case CatalogImporterRegistry.fetch_builtin_importer(
             contribution.importer_key,
             contribution.importer_version
           ) do
        {:ok, registration} -> [registration]
        _invalid_or_unsupported -> []
      end
    end)
  end

  @spec fetch_catalog_importer(binary(), pos_integer() | :latest | nil) ::
          {:ok, CatalogImporterRegistry.importer_registration()}
          | {:error, catalog_importer_fetch_error()}
  def fetch_catalog_importer(importer_key, version \\ :latest)

  def fetch_catalog_importer(importer_key, version) when is_binary(importer_key) do
    with {:ok, contribution} <- fetch_catalog_importer_contribution(importer_key, version) do
      CatalogImporterRegistry.fetch_builtin_importer(
        contribution.importer_key,
        contribution.importer_version
      )
    end
  end

  def fetch_catalog_importer(_importer_key, _version),
    do: {:error, :unknown_catalog_importer_contribution}

  @spec detect_catalog_importer(binary(), binary() | nil) ::
          {:ok, CatalogImporterRegistry.importer_registration()}
          | {:error, :no_matching_importer}
  def detect_catalog_importer(filename, media_type)
      when is_binary(filename) and (is_binary(media_type) or is_nil(media_type)) do
    CatalogImporterRegistry.detect_importer(filename, media_type, catalog_importers())
  end

  @spec widget_types() :: [WidgetType.t()]
  def widget_types do
    Enum.flat_map(widget_type_contributions(), fn contribution ->
      case WidgetRegistry.fetch_type(
             contribution.widget_type_id,
             contribution.widget_type_version
           ) do
        {:ok, widget_type} -> [widget_type]
        _invalid_or_unsupported -> []
      end
    end)
  end

  @spec fetch_widget_type(binary(), pos_integer() | :latest | nil) ::
          {:ok, WidgetType.t()} | {:error, widget_type_fetch_error()}
  def fetch_widget_type(widget_type_id, version \\ :latest)

  def fetch_widget_type(widget_type_id, version) when is_binary(widget_type_id) do
    with {:ok, contribution} <- fetch_widget_type_contribution(widget_type_id, version) do
      WidgetRegistry.fetch_type(
        contribution.widget_type_id,
        contribution.widget_type_version
      )
    end
  end

  def fetch_widget_type(_widget_type_id, _version),
    do: {:error, :unknown_widget_type_contribution}

  @spec source_adapters() :: [SourceAdapterDefinition.t()]
  def source_adapters do
    Enum.flat_map(source_adapter_contributions(), fn contribution ->
      case DefaultSourceAdapters.fetch_definition(
             contribution.logical_source,
             contribution.source_adapter_version
           ) do
        {:ok, definition} -> [definition]
        _invalid_or_unsupported -> []
      end
    end)
  end

  @spec fetch_source_adapter(atom(), pos_integer() | :latest | nil) ::
          {:ok, SourceAdapterDefinition.t()} | {:error, source_adapter_fetch_error()}
  def fetch_source_adapter(logical_source, version \\ :latest)

  def fetch_source_adapter(logical_source, version) when is_atom(logical_source) do
    with {:ok, contribution} <- fetch_source_adapter_contribution(logical_source, version) do
      DefaultSourceAdapters.fetch_definition(
        contribution.logical_source,
        contribution.source_adapter_version
      )
    end
  end

  def fetch_source_adapter(_logical_source, _version),
    do: {:error, :unknown_source_adapter_contribution}

  defp contributions_of_type(contribution_module) do
    available()
    |> Enum.flat_map(& &1.contributions)
    |> Enum.filter(&is_struct(&1, contribution_module))
  end

  defp fetch_application_contribution(application_key, version) do
    contributions =
      Enum.filter(application_contributions(), &(&1.application_key == application_key))

    case {contributions, version} do
      {[], _version} ->
        {:error, :unknown_application_contribution}

      {contributions, requested_version} when requested_version in [:latest, nil] ->
        {:ok, Enum.max_by(contributions, & &1.application_version)}

      {contributions, requested_version} when is_integer(requested_version) ->
        case Enum.find(contributions, &(&1.application_version == requested_version)) do
          %ApplicationContribution{} = contribution -> {:ok, contribution}
          nil -> {:error, :unsupported_application_contribution_version}
        end

      {_contributions, _version} ->
        {:error, :unsupported_application_contribution_version}
    end
  end

  defp fetch_transport_kind_contribution(transport_kind_key, version) do
    contributions =
      Enum.filter(
        transport_kind_contributions(),
        &(&1.transport_kind_key == transport_kind_key)
      )

    fetch_contribution_version(
      contributions,
      version,
      & &1.transport_kind_version,
      :unknown_transport_kind_contribution,
      :unsupported_transport_kind_contribution_version
    )
  end

  defp fetch_provider_connector_contribution(provider_connector_key, version) do
    contributions =
      Enum.filter(
        provider_connector_contributions(),
        &(&1.provider_connector_key == provider_connector_key)
      )

    fetch_contribution_version(
      contributions,
      version,
      & &1.provider_connector_version,
      :unknown_provider_connector_contribution,
      :unsupported_provider_connector_contribution_version
    )
  end

  defp fetch_catalog_importer_contribution(importer_key, version) do
    contributions =
      Enum.filter(catalog_importer_contributions(), &(&1.importer_key == importer_key))

    fetch_contribution_version(
      contributions,
      version,
      & &1.importer_version,
      :unknown_catalog_importer_contribution,
      :unsupported_catalog_importer_contribution_version
    )
  end

  defp fetch_widget_type_contribution(widget_type_id, version) do
    contributions =
      Enum.filter(widget_type_contributions(), &(&1.widget_type_id == widget_type_id))

    fetch_contribution_version(
      contributions,
      version,
      & &1.widget_type_version,
      :unknown_widget_type_contribution,
      :unsupported_widget_type_contribution_version
    )
  end

  defp fetch_source_adapter_contribution(logical_source, version) do
    contributions =
      Enum.filter(source_adapter_contributions(), &(&1.logical_source == logical_source))

    fetch_contribution_version(
      contributions,
      version,
      & &1.source_adapter_version,
      :unknown_source_adapter_contribution,
      :unsupported_source_adapter_contribution_version
    )
  end

  defp fetch_contribution_version(
         [],
         _version,
         _version_getter,
         unknown_error,
         _unsupported_error
       ),
       do: {:error, unknown_error}

  defp fetch_contribution_version(
         contributions,
         version,
         version_getter,
         _unknown_error,
         _unsupported_error
       )
       when version in [:latest, nil],
       do: {:ok, Enum.max_by(contributions, version_getter)}

  defp fetch_contribution_version(
         contributions,
         version,
         version_getter,
         _unknown_error,
         unsupported_error
       )
       when is_integer(version) do
    case Enum.find(contributions, &(version_getter.(&1) == version)) do
      nil -> {:error, unsupported_error}
      contribution -> {:ok, contribution}
    end
  end

  defp fetch_contribution_version(
         _contributions,
         _version,
         _version_getter,
         _unknown_error,
         unsupported_error
       ),
       do: {:error, unsupported_error}

  defp resolved_packages do
    Enum.filter(Registry.available(), &(validate_package(&1) == :ok))
  end

  defp unique_contribution_ownership?(packages) do
    contribution_ids =
      packages
      |> Enum.flat_map(& &1.contributions)
      |> Enum.map(&contribution_id/1)

    length(Enum.uniq(contribution_ids)) == length(contribution_ids)
  end

  defp unique_package_ownership?(packages) do
    package_ids = Enum.map(packages, & &1.package_id)
    length(Enum.uniq(package_ids)) == length(package_ids)
  end

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

  defp validate_dependencies(%ExtensionPackage{} = package) do
    Enum.reduce_while(package.dependencies, :ok, fn dependency, :ok ->
      case validate_dependency(dependency) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_dependency(%PackageDependency{} = dependency) do
    case Enum.find(Registry.all(), &(&1.package_id == dependency.package_id)) do
      %ExtensionPackage{version: version} = package when version >= dependency.minimum_version ->
        ExtensionPackage.validate(package)

      nil when not dependency.required ->
        :ok

      _missing_or_unsupported ->
        {:error, :invalid_extension_package_dependency}
    end
  end

  defp validate_contributions(%ExtensionPackage{} = package) do
    Enum.reduce_while(package.contributions, :ok, fn contribution, :ok ->
      case validate_contribution(package, contribution) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_contribution(
         %ExtensionPackage{} = package,
         %ApplicationContribution{} = contribution
       ) do
    with {:ok, definition} <-
           ApplicationRegistry.fetch(
             contribution.application_key,
             contribution.application_version
           ),
         true <- definition.application_key == contribution.application_key,
         true <- definition.version == contribution.application_version,
         true <-
           definition.surfaces == [] or
             Map.has_key?(package.compatibility, :cadence_surface_contract) do
      :ok
    else
      _invalid -> {:error, :invalid_application_contribution}
    end
  end

  defp validate_contribution(
         %ExtensionPackage{},
         %CapabilityContribution{} = contribution
       ) do
    with {:ok, %Descriptor{} = descriptor} <-
           DefinitionRegistry.fetch_descriptor(
             DefinitionRegistry.default(),
             contribution.family_key,
             contribution.family_version
           ),
         true <- descriptor.kind == contribution.kind do
      :ok
    else
      _invalid -> {:error, :invalid_capability_contribution}
    end
  end

  defp validate_contribution(
         %ExtensionPackage{},
         %CatalogImporterContribution{} = contribution
       ) do
    with {:ok, %{descriptor: %ImporterDescriptor{} = descriptor}} <-
           CatalogImporterRegistry.fetch_builtin_importer(
             contribution.importer_key,
             contribution.importer_version
           ),
         :ok <- ImporterDescriptor.validate(descriptor),
         true <- descriptor.trust == :first_party,
         true <- descriptor.importer_key == contribution.importer_key,
         true <- descriptor.version == contribution.importer_version do
      :ok
    else
      _invalid -> {:error, :invalid_catalog_importer_contribution}
    end
  end

  defp validate_contribution(
         %ExtensionPackage{},
         %TransportKindContribution{} = contribution
       ) do
    with {:ok, %TransportKindDefinition{} = definition} <-
           TransportKind.resolve_form_value(
             contribution.transport_kind_key,
             contribution.transport_kind_version
           ),
         true <- definition.form_value == contribution.transport_kind_key,
         true <- definition.version == contribution.transport_kind_version do
      :ok
    else
      _invalid -> {:error, :invalid_transport_kind_contribution}
    end
  end

  defp validate_contribution(
         %ExtensionPackage{},
         %ProviderConnectorContribution{} = contribution
       ) do
    with {:ok, %ProviderConnectorDefinition{} = definition} <-
           ProviderConnectorRegistry.fetch_definition(
             contribution.provider_connector_key,
             contribution.provider_connector_version
           ),
         true <- definition.form_value == contribution.provider_connector_key,
         true <- definition.version == contribution.provider_connector_version do
      :ok
    else
      _invalid -> {:error, :invalid_provider_connector_contribution}
    end
  end

  defp validate_contribution(
         %ExtensionPackage{},
         %WidgetTypeContribution{} = contribution
       ) do
    with {:ok, %WidgetType{} = widget_type} <-
           WidgetRegistry.fetch_type(
             contribution.widget_type_id,
             contribution.widget_type_version
           ),
         :ok <- WidgetType.validate(widget_type),
         true <- widget_type.widget_type_id == contribution.widget_type_id,
         true <- widget_type.version == contribution.widget_type_version do
      :ok
    else
      _invalid -> {:error, :invalid_widget_type_contribution}
    end
  end

  defp validate_contribution(
         %ExtensionPackage{},
         %SourceAdapterContribution{} = contribution
       ) do
    with {:ok, %SourceAdapterDefinition{} = definition} <-
           DefaultSourceAdapters.fetch_definition(
             contribution.logical_source,
             contribution.source_adapter_version
           ),
         :ok <- SourceAdapterDefinition.validate(definition),
         true <- definition.logical_source == contribution.logical_source,
         true <- definition.version == contribution.source_adapter_version do
      :ok
    else
      _invalid -> {:error, :invalid_source_adapter_contribution}
    end
  end

  defp validate_contribution(%ExtensionPackage{}, _contribution),
    do: {:error, :invalid_extension_package_contribution}
end
