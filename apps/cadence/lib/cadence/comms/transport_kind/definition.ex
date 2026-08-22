defmodule Cadence.Comms.TransportKind.Definition do
  @moduledoc "Typed registry entry for one compiled first-party transport kind."

  alias Cadence.Comms.Transport
  alias Cadence.Extensions.Presentation.ConfigurationDefinition

  @type t :: %__MODULE__{
          form_value: binary(),
          version: pos_integer(),
          kind: Transport.transport_kind(),
          adapter_key: Transport.adapter_key(),
          label: binary(),
          description: binary(),
          module: module(),
          configuration: ConfigurationDefinition.t()
        }

  @enforce_keys [
    :form_value,
    :version,
    :kind,
    :adapter_key,
    :label,
    :description,
    :module,
    :configuration
  ]

  defstruct [
    :form_value,
    :version,
    :kind,
    :adapter_key,
    :label,
    :description,
    :module,
    :configuration
  ]

  @required_callbacks [
    definition: 0,
    normalize_config: 1,
    validate_config: 1,
    display_summary: 1,
    from_delivery_profile: 1,
    materialize_provider_profile: 1
  ]

  @spec validate(t()) :: :ok | {:error, :invalid_transport_kind_definition}
  def validate(%__MODULE__{} = definition) do
    with true <- valid_text?(definition.form_value),
         true <- is_integer(definition.version) and definition.version > 0,
         true <- is_atom(definition.kind) and not is_nil(definition.kind),
         true <- is_atom(definition.adapter_key) and not is_nil(definition.adapter_key),
         true <- valid_text?(definition.label),
         true <- valid_text?(definition.description),
         true <- valid_module?(definition.module),
         :ok <- ConfigurationDefinition.validate(definition.configuration) do
      :ok
    else
      _invalid -> {:error, :invalid_transport_kind_definition}
    end
  end

  def validate(_definition), do: {:error, :invalid_transport_kind_definition}

  defp valid_module?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(@required_callbacks, fn {function, arity} ->
        function_exported?(module, function, arity)
      end)
  end

  defp valid_module?(_module), do: false
  defp valid_text?(value), do: is_binary(value) and value != ""
end
