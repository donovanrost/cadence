defmodule Cadence.Contacts.ProviderClients.Definition do
  @moduledoc "Typed registry entry for one compiled provider control-plane connector."

  alias Cadence.Contacts.ProviderClient
  alias Cadence.Extensions.Presentation.ConfigurationDefinition

  @type t :: %__MODULE__{
          form_value: binary(),
          version: pos_integer(),
          provider_type: atom(),
          client_key: atom(),
          label: binary(),
          description: binary(),
          module: module(),
          configuration: ConfigurationDefinition.t(),
          account_defaults: %{binary() => binary()}
        }

  @enforce_keys [
    :form_value,
    :version,
    :provider_type,
    :client_key,
    :label,
    :description,
    :module,
    :configuration
  ]

  defstruct [
    :form_value,
    :version,
    :provider_type,
    :client_key,
    :label,
    :description,
    :module,
    :configuration,
    account_defaults: %{}
  ]

  @spec validate(t()) :: :ok | {:error, :invalid_provider_connector_definition}
  def validate(%__MODULE__{} = definition) do
    with true <- valid_text?(definition.form_value),
         true <- is_integer(definition.version) and definition.version > 0,
         true <- is_atom(definition.provider_type) and not is_nil(definition.provider_type),
         true <- is_atom(definition.client_key) and not is_nil(definition.client_key),
         true <- valid_text?(definition.label),
         true <- valid_text?(definition.description),
         true <- valid_module?(definition.module),
         true <- valid_account_defaults?(definition.account_defaults),
         :ok <- ConfigurationDefinition.validate(definition.configuration) do
      :ok
    else
      _invalid -> {:error, :invalid_provider_connector_definition}
    end
  end

  def validate(_definition), do: {:error, :invalid_provider_connector_definition}

  defp valid_module?(module) when is_atom(module) and not is_nil(module) do
    optional_callbacks = ProviderClient.behaviour_info(:optional_callbacks)

    Code.ensure_loaded?(module) and
      ProviderClient.behaviour_info(:callbacks)
      |> Enum.reject(&(&1 in optional_callbacks))
      |> Enum.all?(fn {function, arity} -> function_exported?(module, function, arity) end)
  end

  defp valid_module?(_module), do: false

  defp valid_account_defaults?(defaults) when is_map(defaults) do
    Enum.all?(defaults, fn {key, value} -> is_binary(key) and is_binary(value) end)
  end

  defp valid_account_defaults?(_defaults), do: false
  defp valid_text?(value), do: is_binary(value) and value != ""
end
