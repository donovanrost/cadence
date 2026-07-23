defmodule Cadence.Runtime.ContactPathSpec do
  @moduledoc """
  Exact directional path input for one realized Contact data-plane runtime.
  """

  alias Cadence.Runtime.{ProviderBindingSpec, TransportBindingSpec}

  @type direction :: :uplink | :downlink
  @type selection_role :: :selected | :candidate | :contributing

  @type t :: %__MODULE__{
          path_id: binary(),
          direction: direction(),
          selection_role: selection_role(),
          source_endpoint_ref: binary() | nil,
          provider_path_ref: binary() | nil,
          provider_bindings: [ProviderBindingSpec.t()],
          transport_bindings: [TransportBindingSpec.t()],
          metadata: map()
        }

  @enforce_keys [
    :path_id,
    :direction,
    :selection_role,
    :provider_bindings,
    :transport_bindings,
    :metadata
  ]
  defstruct @enforce_keys ++ [source_endpoint_ref: nil, provider_path_ref: nil]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    path_id = value(attrs, :path_id)
    direction = value(attrs, :direction)
    selection_role = value(attrs, :selection_role, :candidate)
    source_endpoint_ref = value(attrs, :source_endpoint_ref)
    provider_path_ref = value(attrs, :provider_path_ref)
    metadata = value(attrs, :metadata, %{})

    with :ok <- non_empty_binary(path_id, :path_id),
         :ok <- member(direction, [:uplink, :downlink], :direction),
         :ok <- member(selection_role, [:selected, :candidate, :contributing], :selection_role),
         :ok <- optional_binary(source_endpoint_ref, :source_endpoint_ref),
         :ok <- optional_binary(provider_path_ref, :provider_path_ref),
         {:ok, provider_bindings} <-
           build_list(value(attrs, :provider_bindings, []), ProviderBindingSpec),
         {:ok, transport_bindings} <-
           build_list(value(attrs, :transport_bindings, []), TransportBindingSpec),
         :ok <- map(metadata, :metadata) do
      {:ok,
       %__MODULE__{
         path_id: path_id,
         direction: direction,
         selection_role: selection_role,
         source_endpoint_ref: source_endpoint_ref,
         provider_path_ref: provider_path_ref,
         provider_bindings: provider_bindings,
         transport_bindings: transport_bindings,
         metadata: metadata
       }}
    end
  end

  defp build_list(values, module) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case build(value, module) do
        {:ok, built} -> {:cont, {:ok, [built | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end)
  end

  defp build_list(_values, _module), do: invalid(:bindings)

  defp build(value, module) when is_struct(value, module), do: {:ok, value}
  defp build(value, module) when is_map(value), do: module.new(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp non_empty_binary(value, _field) when is_binary(value) and value != "", do: :ok
  defp non_empty_binary(_value, field), do: invalid(field)
  defp optional_binary(nil, _field), do: :ok
  defp optional_binary(value, _field) when is_binary(value), do: :ok
  defp optional_binary(_value, field), do: invalid(field)

  defp member(value, allowed, field) do
    if value in allowed, do: :ok, else: invalid(field)
  end

  defp map(value, _field) when is_map(value), do: :ok
  defp map(_value, field), do: invalid(field)
  defp invalid(field), do: {:error, {:invalid_contact_path_spec, field}}
end
