defmodule Cadence.Runtime.TransportBindingSpec do
  @moduledoc """
  Exact transport-extension input embedded in a realized Contact runtime spec.
  """

  @type target_scope :: :path | :transport

  @type t :: %__MODULE__{
          transport_binding_id: binary(),
          family_key: atom(),
          target_scope: target_scope(),
          configuration: term(),
          metadata: map()
        }

  @enforce_keys [
    :transport_binding_id,
    :family_key,
    :target_scope,
    :configuration,
    :metadata
  ]
  defstruct @enforce_keys

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    transport_binding_id = value(attrs, :transport_binding_id)
    family_key = value(attrs, :family_key)
    target_scope = value(attrs, :target_scope, :path)
    metadata = value(attrs, :metadata, %{})

    with :ok <- non_empty_binary(transport_binding_id, :transport_binding_id),
         :ok <- atom(family_key, :family_key),
         :ok <- target_scope(target_scope),
         :ok <- map(metadata, :metadata) do
      {:ok,
       %__MODULE__{
         transport_binding_id: transport_binding_id,
         family_key: family_key,
         target_scope: target_scope,
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
  defp target_scope(value) when value in [:path, :transport], do: :ok
  defp target_scope(_value), do: invalid(:target_scope)
  defp map(value, _field) when is_map(value), do: :ok
  defp map(_value, field), do: invalid(field)
  defp invalid(field), do: {:error, {:invalid_transport_binding_spec, field}}
end
