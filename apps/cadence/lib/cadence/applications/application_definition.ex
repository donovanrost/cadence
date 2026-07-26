defmodule Cadence.Applications.ApplicationDefinition do
  @moduledoc """
  Versioned product definition for an operator-facing Cadence application.

  The definition composes configuration, lifecycle, status, presentation, and
  runtime contribution contracts without turning them into one universal
  callback.
  """

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDependency,
    LifecycleContract,
    ResourceContract,
    StatusPlacement,
    SurfaceDefinition
  }

  @type availability :: :available | :roadmap
  @type trust :: :first_party
  @type scope :: ActionDefinition.scope()

  @type t :: %__MODULE__{
          application_key: binary(),
          version: pos_integer(),
          display_name: binary(),
          description: binary(),
          trust: trust(),
          availability: availability(),
          installable_scopes: [scope()],
          dependencies: [ApplicationDependency.t()],
          configuration_contract: map(),
          resource_contract: ResourceContract.t(),
          lifecycle_contract: LifecycleContract.t(),
          status_query_id: binary() | nil,
          status_placements: [StatusPlacement.t()],
          preflight_query_id: binary() | nil,
          actions: [ActionDefinition.t()],
          surfaces: [SurfaceDefinition.t()],
          capability_contributions: [map()]
        }

  @enforce_keys [
    :application_key,
    :version,
    :display_name,
    :description,
    :trust,
    :availability,
    :installable_scopes
  ]

  defstruct [
    :application_key,
    :version,
    :display_name,
    :description,
    :trust,
    :availability,
    :status_query_id,
    :preflight_query_id,
    installable_scopes: [],
    dependencies: [],
    configuration_contract: %{},
    resource_contract: %ResourceContract{},
    lifecycle_contract: %LifecycleContract{},
    status_placements: [],
    actions: [],
    surfaces: [],
    capability_contributions: []
  ]

  @scopes [:organization, :mission, :spacecraft, :source_endpoint, :transport]
  @capability_kinds [:semantic_handler, :managed_application, :projection, :transport_extension]
  @max_dependencies 16
  @max_status_placements 8
  @max_actions 32
  @max_surfaces 32
  @max_capability_contributions 32

  @spec available?(t()) :: boolean()
  def available?(%__MODULE__{availability: :available}), do: true
  def available?(%__MODULE__{}), do: false

  @spec fetch_action(t(), binary()) ::
          {:ok, ActionDefinition.t()} | {:error, :undeclared_application_action}
  def fetch_action(%__MODULE__{actions: actions}, action_id)
      when is_list(actions) and is_binary(action_id) do
    case Enum.find(actions, &match?(%ActionDefinition{action_id: ^action_id}, &1)) do
      %ActionDefinition{} = action -> {:ok, action}
      nil -> {:error, :undeclared_application_action}
    end
  end

  def fetch_action(%__MODULE__{}, _action_id),
    do: {:error, :undeclared_application_action}

  @spec validate(t()) :: :ok | {:error, :invalid_application_definition}
  def validate(%__MODULE__{} = definition) do
    with true <- valid_text?(definition.application_key),
         true <- positive_integer?(definition.version),
         true <- valid_text?(definition.display_name),
         true <- valid_text?(definition.description),
         true <- definition.trust == :first_party,
         true <- definition.availability in [:available, :roadmap],
         true <- valid_installable_scopes?(definition.installable_scopes),
         true <- valid_dependencies?(definition.dependencies, definition.application_key),
         true <- valid_configuration_contract?(definition.configuration_contract),
         :ok <- ResourceContract.validate(definition.resource_contract),
         :ok <- LifecycleContract.validate(definition.lifecycle_contract),
         true <- optional_text?(definition.status_query_id),
         true <- valid_status_placements?(definition),
         true <- optional_text?(definition.preflight_query_id),
         true <- valid_actions?(definition.actions, definition.installable_scopes),
         true <- distinct_action_contracts?(definition),
         true <- valid_surfaces?(definition),
         true <- valid_capability_contributions?(definition.capability_contributions) do
      :ok
    else
      _invalid -> {:error, :invalid_application_definition}
    end
  end

  def validate(_definition), do: {:error, :invalid_application_definition}

  defp valid_installable_scopes?(scopes) when is_list(scopes) do
    scopes != [] and Enum.all?(scopes, &(&1 in @scopes)) and
      length(Enum.uniq(scopes)) == length(scopes)
  end

  defp valid_installable_scopes?(_scopes), do: false

  defp valid_dependencies?(dependencies, application_key) when is_list(dependencies) do
    identities = Enum.map(dependencies, &dependency_identity/1)

    length(dependencies) <= @max_dependencies and
      Enum.all?(dependencies, &(ApplicationDependency.validate(&1) == :ok)) and
      Enum.all?(dependencies, &(&1.application_key != application_key)) and
      length(Enum.uniq(identities)) == length(identities)
  end

  defp valid_dependencies?(_dependencies, _application_key), do: false

  defp valid_status_placements?(%__MODULE__{} = definition)
       when is_list(definition.status_placements) do
    identities = Enum.map(definition.status_placements, &status_placement_identity/1)

    length(definition.status_placements) <= @max_status_placements and
      Enum.all?(definition.status_placements, &(StatusPlacement.validate(&1) == :ok)) and
      Enum.all?(definition.status_placements, &(&1.scope in definition.installable_scopes)) and
      length(Enum.uniq(identities)) == length(identities) and
      (definition.status_placements == [] or valid_text?(definition.status_query_id))
  end

  defp valid_status_placements?(%__MODULE__{}), do: false

  defp status_placement_identity(%StatusPlacement{placement: placement, scope: scope}),
    do: {placement, scope}

  defp status_placement_identity(_status_placement), do: nil

  defp dependency_identity(%ApplicationDependency{
         application_key: application_key,
         scope: scope
       }),
       do: {application_key, scope}

  defp dependency_identity(_dependency), do: nil

  defp valid_configuration_contract?(contract) when map_size(contract) == 0, do: true

  defp valid_configuration_contract?(contract) when is_map(contract) do
    Enum.all?(Map.keys(contract), &(&1 in [:schema_id, :version])) and
      valid_text?(Map.get(contract, :schema_id)) and
      positive_integer?(Map.get(contract, :version))
  end

  defp valid_configuration_contract?(_contract), do: false

  defp valid_actions?(actions, installable_scopes) when is_list(actions) do
    action_ids = Enum.map(actions, &action_id/1)

    length(actions) <= @max_actions and
      Enum.all?(actions, &(ActionDefinition.validate(&1) == :ok)) and
      Enum.all?(actions, &(&1.scope in installable_scopes)) and
      length(Enum.uniq(action_ids)) == length(action_ids)
  end

  defp valid_actions?(_actions, _installable_scopes), do: false

  defp action_id(%ActionDefinition{action_id: action_id}), do: action_id
  defp action_id(_action), do: nil

  defp distinct_action_contracts?(%__MODULE__{} = definition) do
    domain_action_ids = Enum.map(definition.actions, & &1.action_id)
    Enum.all?(domain_action_ids, &(&1 not in definition.lifecycle_contract.actions))
  end

  defp valid_surfaces?(%__MODULE__{} = definition) when is_list(definition.surfaces) do
    surface_identities = Enum.map(definition.surfaces, &surface_identity/1)
    declared_action_ids = declared_action_ids(definition)

    length(definition.surfaces) <= @max_surfaces and
      Enum.all?(definition.surfaces, &(SurfaceDefinition.validate(&1) == :ok)) and
      Enum.all?(definition.surfaces, &(&1.scope in definition.installable_scopes)) and
      length(Enum.uniq(surface_identities)) == length(surface_identities) and
      Enum.all?(definition.surfaces, fn surface ->
        Enum.all?(surface.actions, &MapSet.member?(declared_action_ids, &1))
      end) and workspace_surface_coverage?(definition)
  end

  defp valid_surfaces?(%__MODULE__{}), do: false

  defp surface_identity(%SurfaceDefinition{scope: scope, surface_id: surface_id}),
    do: {scope, surface_id}

  defp surface_identity(_surface), do: nil

  defp declared_action_ids(%__MODULE__{} = definition) do
    definition.actions
    |> Enum.map(& &1.action_id)
    |> Kernel.++(definition.lifecycle_contract.actions)
    |> MapSet.new()
  end

  defp workspace_surface_coverage?(%__MODULE__{availability: :roadmap}), do: true

  defp workspace_surface_coverage?(%__MODULE__{} = definition) do
    Enum.all?(definition.installable_scopes, fn scope ->
      Enum.any?(definition.surfaces, fn surface ->
        surface.scope == scope and surface.placement == :application_workspace
      end)
    end)
  end

  defp valid_capability_contributions?(contributions) when is_list(contributions) do
    length(contributions) <= @max_capability_contributions and
      Enum.all?(contributions, &valid_capability_contribution?/1)
  end

  defp valid_capability_contributions?(_contributions), do: false

  defp valid_capability_contribution?(%{family_key: family_key, kind: kind}) do
    is_atom(family_key) and not is_nil(family_key) and kind in @capability_kinds
  end

  defp valid_capability_contribution?(_contribution), do: false

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
