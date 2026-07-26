defmodule Cadence.Reads.Applications.Inventory do
  @moduledoc """
  Composes application-package definitions, host installation lifecycle, and
  status providers into one inventory projection.

  Catalog inventories expose every available application at a host scope.
  Declared inventories preserve a profile's application keys, including
  extension keys whose package is not present in this Cadence deployment.
  """

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    HostContext,
    Status
  }

  alias Cadence.Auth.Scope
  alias Cadence.Reads.Applications
  alias Cadence.Reads.Applications.InventoryItem

  @spec catalog(Scope.t(), HostContext.t(), [ApplicationDefinition.t()]) ::
          {:ok, [InventoryItem.t()]} | {:error, term()}
  def catalog(%Scope{} = current_scope, %HostContext{} = host_context, definitions)
      when is_list(definitions) do
    with :ok <- validate_definitions(definitions, host_context),
         {:ok, installations} <- installation_map(current_scope, host_context) do
      known_items =
        Enum.map(definitions, fn definition ->
          installation = Map.get(installations, definition.application_key)

          definition
          |> exact_definition(installation)
          |> known_item(definition, installation, current_scope, host_context, false)
        end)

      known_keys = MapSet.new(definitions, & &1.application_key)

      orphaned_items =
        installations
        |> Map.values()
        |> Enum.reject(&MapSet.member?(known_keys, &1.application_key))
        |> Enum.sort_by(& &1.application_key)
        |> Enum.map(&unknown_item(&1.application_key, %{}, &1, false))

      {:ok, known_items ++ orphaned_items}
    end
  end

  def catalog(%Scope{}, %HostContext{}, _definitions),
    do: {:error, :invalid_application_inventory_definitions}

  @spec declared(Scope.t(), HostContext.t(), map(), [ApplicationDefinition.t()]) ::
          {:ok, [InventoryItem.t()]} | {:error, term()}
  def declared(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        declarations,
        definitions
      )
      when is_map(declarations) and is_list(definitions) do
    with :ok <- validate_definitions(definitions, host_context),
         {:ok, installations} <- installation_map(current_scope, host_context) do
      definitions = Map.new(definitions, &{&1.application_key, &1})

      items =
        declarations
        |> Enum.sort()
        |> Enum.map(fn {application_key, metadata} ->
          installation = Map.get(installations, application_key)

          declared_item(
            application_key,
            metadata,
            installation,
            definitions,
            current_scope,
            host_context,
            true
          )
        end)

      declared_keys =
        MapSet.new(declarations, fn {application_key, _metadata} -> application_key end)

      retained_items =
        installations
        |> Map.values()
        |> Enum.reject(&MapSet.member?(declared_keys, &1.application_key))
        |> Enum.sort_by(& &1.application_key)
        |> Enum.map(fn installation ->
          retained_item(installation, definitions, current_scope, host_context)
        end)

      {:ok, items ++ retained_items}
    end
  end

  def declared(%Scope{}, %HostContext{}, _declarations, _definitions),
    do: {:error, :invalid_application_declarations}

  @spec summary([InventoryItem.t()]) :: Status.t()
  def summary([]) do
    %Status{state: :none_declared, label: "None declared", tone: :info}
  end

  def summary([%InventoryItem{status: %Status{} = status}]), do: status

  def summary(items) when is_list(items) do
    ready_count = Enum.count(items, &(&1.status.tone == :ready))
    total_count = length(items)

    %Status{
      state: aggregate_state(items, ready_count, total_count),
      label: "#{ready_count} of #{total_count} ready",
      tone: aggregate_tone(items, ready_count, total_count),
      facts:
        Enum.map(items, fn item ->
          %{
            id: item.application_key,
            label: item.display_name,
            value: item.status.label
          }
        end)
    }
  end

  defp declared_item(
         application_key,
         metadata,
         installation,
         definitions,
         current_scope,
         host_context,
         declared?
       ) do
    case resolve_definition(application_key, installation, definitions) do
      {:ok, definition, exact?} ->
        known_item(
          {definition, exact?},
          definition,
          installation,
          current_scope,
          host_context,
          declared?
        )

      {:error, _reason} ->
        unknown_item(application_key, metadata, installation, declared?)
    end
  end

  defp retained_item(installation, definitions, current_scope, host_context) do
    case Map.fetch(definitions, installation.application_key) do
      {:ok, definition} ->
        definition
        |> exact_definition(installation)
        |> known_item(definition, installation, current_scope, host_context, false)

      :error ->
        unknown_item(installation.application_key, %{}, installation, false)
    end
  end

  defp exact_definition(definition, nil), do: {definition, true}

  defp exact_definition(
         %ApplicationDefinition{version: version} = definition,
         %ApplicationInstallation{application_version: version}
       ),
       do: {definition, true}

  defp exact_definition(definition, %ApplicationInstallation{}), do: {definition, false}

  defp resolve_definition(application_key, installation, definitions) do
    case Map.fetch(definitions, application_key) do
      {:ok, definition} ->
        {definition, exact?} = exact_definition(definition, installation)
        {:ok, definition, exact?}

      :error ->
        {:error, :unknown_application_definition}
    end
  end

  defp known_item(
         {definition, exact?},
         display_definition,
         installation,
         current_scope,
         host_context,
         declared?
       ) do
    lifecycle_state = installation && installation.lifecycle_state

    %InventoryItem{
      application_key: display_definition.application_key,
      application_version: application_version(display_definition, installation),
      display_name: display_definition.display_name,
      description: display_definition.description,
      definition: definition,
      installation: installation,
      lifecycle_state: lifecycle_state,
      declared?: declared?,
      installable?: installable?(display_definition, host_context),
      manageable?: lifecycle_state == :installed and exact?,
      uninstallable?: lifecycle_state in [:installed, :disabled],
      status:
        inventory_status(
          definition,
          installation,
          exact?,
          current_scope,
          host_context
        )
    }
  end

  defp unknown_item(application_key, metadata, installation, declared?) do
    metadata = if is_map(metadata), do: metadata, else: %{}

    %InventoryItem{
      application_key: application_key,
      application_version: installation && installation.application_version,
      display_name: Map.get(metadata, "display_name", humanize_application_key(application_key)),
      description: Map.get(metadata, "description", "Custom product application."),
      definition: nil,
      installation: installation,
      lifecycle_state: installation && installation.lifecycle_state,
      declared?: declared?,
      installable?: false,
      manageable?: false,
      uninstallable?:
        not is_nil(installation) and installation.lifecycle_state in [:installed, :disabled],
      status: Status.unavailable()
    }
  end

  defp inventory_status(
         definition,
         %ApplicationInstallation{lifecycle_state: :installed},
         true,
         current_scope,
         host_context
       ) do
    case Applications.load_status(current_scope, definition, host_context) do
      {:ok, status} -> status
      {:error, _reason} -> Status.unavailable()
    end
  end

  defp inventory_status(
         definition,
         %ApplicationInstallation{
           lifecycle_state: :installed,
           application_version: installed_version
         },
         false,
         _current_scope,
         _host_context
       ) do
    %Status{
      state: :upgrade_required,
      label: "Upgrade required",
      tone: :attention,
      facts: [
        %{
          id: "installed_version",
          label: "Installed version",
          value: "v#{installed_version}"
        },
        %{
          id: "available_version",
          label: "Available version",
          value: "v#{definition.version}"
        }
      ]
    }
  end

  defp inventory_status(
         _definition,
         %ApplicationInstallation{
           lifecycle_state: :disabled,
           application_version: installed_version
         },
         _exact?,
         _current_scope,
         _host_context
       ) do
    lifecycle_status(:disabled, "Disabled", :blocked, installed_version, "Enable to manage")
  end

  defp inventory_status(
         _definition,
         %ApplicationInstallation{
           lifecycle_state: :uninstalled,
           application_version: installed_version
         },
         _exact?,
         _current_scope,
         _host_context
       ) do
    lifecycle_status(
      :uninstalled,
      "Uninstalled",
      :info,
      installed_version,
      "Reinstall to manage"
    )
  end

  defp inventory_status(
         definition,
         nil,
         _exact?,
         _current_scope,
         _host_context
       ) do
    lifecycle_status(
      :not_installed,
      "Not installed",
      :info,
      definition.version,
      "Install to configure"
    )
  end

  defp lifecycle_status(state, label, tone, version, workspace) do
    %Status{
      state: state,
      label: label,
      tone: tone,
      facts: [
        %{id: "workspace", label: "Workspace", value: workspace},
        %{id: "application_version", label: "Application version", value: "v#{version}"}
      ]
    }
  end

  defp application_version(
         _definition,
         %ApplicationInstallation{application_version: application_version}
       ),
       do: application_version

  defp application_version(%ApplicationDefinition{version: version}, nil), do: version

  defp installable?(%ApplicationDefinition{} = definition, %HostContext{placement: placement}) do
    ApplicationDefinition.available?(definition) and placement in definition.installable_scopes
  end

  defp installation_map(current_scope, host_context) do
    case ApplicationInstallations.list(current_scope, host_context) do
      {:ok, installations} -> {:ok, Map.new(installations, &{&1.application_key, &1})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_definitions(definitions, %HostContext{placement: placement}) do
    identities = Enum.map(definitions, &definition_identity/1)
    valid? = Enum.all?(definitions, &valid_definition?(&1, placement))

    if valid? and length(identities) == length(Enum.uniq(identities)) do
      :ok
    else
      {:error, :invalid_application_inventory_definitions}
    end
  end

  defp valid_definition?(%ApplicationDefinition{} = definition, placement) do
    placement in definition.installable_scopes and
      ApplicationDefinition.validate(definition) == :ok
  end

  defp valid_definition?(_definition, _placement), do: false

  defp definition_identity(%ApplicationDefinition{application_key: application_key}),
    do: application_key

  defp definition_identity(_definition), do: nil

  defp aggregate_state(_items, ready_count, total_count) when ready_count == total_count,
    do: :ready

  defp aggregate_state(items, _ready_count, _total_count) do
    if Enum.any?(items, &(&1.status.tone == :blocked)), do: :blocked, else: :attention
  end

  defp aggregate_tone(_items, ready_count, total_count) when ready_count == total_count,
    do: :ready

  defp aggregate_tone(items, _ready_count, _total_count) do
    if Enum.any?(items, &(&1.status.tone == :blocked)), do: :blocked, else: :attention
  end

  defp humanize_application_key(key) do
    key
    |> String.replace(["_", "-", ":"], " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
