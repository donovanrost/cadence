defmodule Cadence.Applications.ApplicationDefinition do
  @moduledoc """
  Versioned product definition for an operator-facing Cadence application.

  Every application is headless: the console's own screens install, configure and show the
  status of it, and the server's domain paths run it. The definition composes configuration,
  resources, status, settings and runtime contributions.
  """

  alias Cadence.Applications.{ResourceContract, SettingsSectionDefinition}

  @type availability :: :available | :roadmap
  @type trust :: :first_party
  @type installation_policy :: :platform | :optional
  @type scope ::
          :organization
          | :user
          | :admin
          | :mission
          | :spacecraft
          | :source_endpoint
          | :transport

  @type t :: %__MODULE__{
          application_key: binary(),
          version: pos_integer(),
          display_name: binary(),
          description: binary(),
          trust: trust(),
          installation_policy: installation_policy(),
          availability: availability(),
          installable_scopes: [scope()],
          configuration_contract: map(),
          resource_contract: ResourceContract.t(),
          status_query_id: binary() | nil,
          settings_sections: [SettingsSectionDefinition.t()],
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
    installation_policy: :optional,
    installable_scopes: [],
    configuration_contract: %{},
    resource_contract: %ResourceContract{},
    settings_sections: [],
    capability_contributions: []
  ]

  @scopes [:organization, :user, :admin, :mission, :spacecraft, :source_endpoint, :transport]
  @capability_kinds [:semantic_handler, :managed_application, :projection, :transport_extension]
  @max_capability_contributions 32

  @spec available?(t()) :: boolean()
  def available?(%__MODULE__{availability: :available}), do: true
  def available?(%__MODULE__{}), do: false

  @doc "Whether a platform definition supports this scope without an installation."
  @spec platform?(t(), scope()) :: boolean()
  def platform?(%__MODULE__{installation_policy: :platform} = definition, scope),
    do: scope in definition.installable_scopes

  def platform?(%__MODULE__{}, _scope), do: false

  @spec validate(t()) :: :ok | {:error, :invalid_application_definition}
  def validate(%__MODULE__{} = definition) do
    with true <- valid_text?(definition.application_key),
         true <- positive_integer?(definition.version),
         true <- valid_text?(definition.display_name),
         true <- valid_text?(definition.description),
         true <- definition.trust == :first_party,
         true <- definition.installation_policy in [:platform, :optional],
         true <- definition.availability in [:available, :roadmap],
         true <- valid_installable_scopes?(definition.installable_scopes),
         true <- valid_configuration_contract?(definition.configuration_contract),
         :ok <- ResourceContract.validate(definition.resource_contract),
         true <- optional_text?(definition.status_query_id),
         true <- valid_settings_sections?(definition.settings_sections),
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

  # An application installed on mission or spacecraft resources can contribute
  # organization defaults without an organization-level installation.
  defp valid_settings_sections?(sections) when is_list(sections) do
    length(sections) <= 8 and
      Enum.all?(sections, &(SettingsSectionDefinition.validate(&1) == :ok)) and
      length(Enum.uniq_by(sections, & &1.id)) == length(sections)
  end

  defp valid_settings_sections?(_sections), do: false

  defp valid_configuration_contract?(contract) when map_size(contract) == 0, do: true

  defp valid_configuration_contract?(contract) when is_map(contract) do
    Enum.all?(Map.keys(contract), &(&1 in [:schema_id, :version])) and
      valid_text?(Map.get(contract, :schema_id)) and
      positive_integer?(Map.get(contract, :version))
  end

  defp valid_configuration_contract?(_contract), do: false

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
