defmodule Cadence.Runtime.ProviderBindingSpec do
  @moduledoc """
  Exact provider adapter input embedded in a realized Contact runtime spec.

  This is a data-plane value object. Control-plane contact models are translated
  into it before a realized Contact is handed to the runtime.
  """

  @type t :: %__MODULE__{
          provider_binding_id: binary(),
          adapter_key: atom(),
          configuration: term(),
          metadata: map()
        }

  @enforce_keys [:provider_binding_id, :adapter_key, :configuration, :metadata]
  defstruct @enforce_keys

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    provider_binding_id = value(attrs, :provider_binding_id)
    adapter_key = value(attrs, :adapter_key)
    metadata = value(attrs, :metadata, %{})

    with :ok <- non_empty_binary(provider_binding_id, :provider_binding_id),
         :ok <- atom(adapter_key, :adapter_key),
         :ok <- map(metadata, :metadata) do
      {:ok,
       %__MODULE__{
         provider_binding_id: provider_binding_id,
         adapter_key: adapter_key,
         configuration: value(attrs, :configuration, %{}),
         metadata: metadata
       }}
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp non_empty_binary(value, _field) when is_binary(value) and value != "", do: :ok
  defp non_empty_binary(_value, field), do: invalid(field)
  defp atom(value, _field) when is_atom(value) and not is_nil(value), do: :ok
  defp atom(_value, field), do: invalid(field)
  defp map(value, _field) when is_map(value), do: :ok
  defp map(_value, field), do: invalid(field)
  defp invalid(field), do: {:error, {:invalid_provider_binding_spec, field}}
end
