defmodule Cadence.Dashboards.SourceAdapterDefinition do
  @moduledoc "Typed registry entry for one compiled built-in dashboard source adapter."

  @type t :: %__MODULE__{
          logical_source: atom(),
          version: pos_integer(),
          label: binary(),
          description: binary(),
          module: module(),
          default_data_source_capabilities: map()
        }

  @enforce_keys [
    :logical_source,
    :version,
    :label,
    :description,
    :module,
    :default_data_source_capabilities
  ]

  defstruct [
    :logical_source,
    :version,
    :label,
    :description,
    :module,
    :default_data_source_capabilities
  ]

  @spec validate(t()) :: :ok | {:error, :invalid_source_adapter_definition}
  def validate(%__MODULE__{} = definition) do
    with true <- is_atom(definition.logical_source) and not is_nil(definition.logical_source),
         true <- is_integer(definition.version) and definition.version > 0,
         true <- valid_text?(definition.label),
         true <- valid_text?(definition.description),
         true <- valid_module?(definition.module),
         true <- is_map(definition.default_data_source_capabilities) do
      :ok
    else
      _invalid -> {:error, :invalid_source_adapter_definition}
    end
  end

  def validate(_definition), do: {:error, :invalid_source_adapter_definition}

  defp valid_module?(module) when is_atom(module) and not is_nil(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :capabilities, 0)

  defp valid_module?(_module), do: false
  defp valid_text?(value), do: is_binary(value) and value != ""
end
