defmodule Cadence.Runtime.RealizedContactRuntimeSpec do
  @moduledoc """
  Exact, immutable start input for one realized Contact data-plane runtime.
  """

  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.ContactPathSpec

  @type t :: %__MODULE__{
          runtime_spec_id: binary(),
          generation: pos_integer(),
          content_sha256: binary(),
          realized_contact_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          scheduled_contact_id: binary() | nil,
          source_endpoint_refs: [binary()],
          contact_intents: [atom()],
          paths: [ContactPathSpec.t()],
          clock_mode: :live | :replay,
          initial_time: DateTime.t() | nil,
          metadata: map()
        }

  @enforce_keys [
    :runtime_spec_id,
    :generation,
    :content_sha256,
    :realized_contact_id,
    :mission_id,
    :source_endpoint_refs,
    :contact_intents,
    :paths,
    :clock_mode,
    :metadata
  ]
  defstruct @enforce_keys ++ [organization_id: nil, scheduled_contact_id: nil, initial_time: nil]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    realized_contact_id = Map.get(attrs, :realized_contact_id)

    runtime_spec_id =
      Map.get(attrs, :runtime_spec_id, "realized_contact_runtime:#{realized_contact_id}")

    generation = Map.get(attrs, :generation, 1)

    with {:ok, paths} <- build_paths(Map.get(attrs, :paths)),
         payload =
           attrs
           |> Map.put(:paths, paths)
           |> Map.drop([:content_sha256, :runtime_spec_id]),
         content_sha256 = ContentHash.term_sha256(payload),
         :ok <- non_empty_binary(runtime_spec_id, :runtime_spec_id),
         :ok <- positive_integer(generation, :generation),
         :ok <- non_empty_binary(realized_contact_id, :realized_contact_id),
         :ok <- non_empty_binary(Map.get(attrs, :mission_id), :mission_id),
         :ok <- atom_list(Map.get(attrs, :contact_intents, []), :contact_intents),
         :ok <- binary_list(Map.get(attrs, :source_endpoint_refs, []), :source_endpoint_refs),
         :ok <- clock_mode(Map.get(attrs, :clock_mode, :live)),
         :ok <- metadata(Map.get(attrs, :metadata, %{})),
         :ok <- exact_hash(Map.get(attrs, :content_sha256, content_sha256), content_sha256) do
      {:ok,
       %__MODULE__{
         runtime_spec_id: runtime_spec_id,
         generation: generation,
         content_sha256: content_sha256,
         realized_contact_id: realized_contact_id,
         organization_id: Map.get(attrs, :organization_id),
         mission_id: Map.get(attrs, :mission_id),
         scheduled_contact_id: Map.get(attrs, :scheduled_contact_id),
         source_endpoint_refs: Map.get(attrs, :source_endpoint_refs, []),
         contact_intents: Map.get(attrs, :contact_intents, []),
         paths: paths,
         clock_mode: Map.get(attrs, :clock_mode, :live),
         initial_time: Map.get(attrs, :initial_time),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  defp non_empty_binary(value, _field) when is_binary(value) and value != "", do: :ok

  defp non_empty_binary(_value, field),
    do: {:error, {:invalid_realized_contact_runtime_spec, field}}

  defp positive_integer(value, _field) when is_integer(value) and value > 0, do: :ok

  defp positive_integer(_value, field),
    do: {:error, {:invalid_realized_contact_runtime_spec, field}}

  defp build_paths(paths) when is_list(paths) and paths != [] do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case build_path(path) do
        {:ok, path} -> {:cont, {:ok, [path | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end)
  end

  defp build_paths(_paths), do: {:error, {:invalid_realized_contact_runtime_spec, :paths}}

  defp build_path(%ContactPathSpec{} = path), do: {:ok, path}
  defp build_path(path) when is_map(path), do: ContactPathSpec.new(path)

  defp atom_list(values, _field) when is_list(values) do
    if Enum.all?(values, &is_atom/1),
      do: :ok,
      else: {:error, {:invalid_realized_contact_runtime_spec, :contact_intents}}
  end

  defp binary_list(values, _field) when is_list(values) do
    if Enum.all?(values, &is_binary/1),
      do: :ok,
      else: {:error, {:invalid_realized_contact_runtime_spec, :source_endpoint_refs}}
  end

  defp clock_mode(mode) when mode in [:live, :replay], do: :ok
  defp clock_mode(_mode), do: {:error, {:invalid_realized_contact_runtime_spec, :clock_mode}}
  defp metadata(value) when is_map(value), do: :ok
  defp metadata(_value), do: {:error, {:invalid_realized_contact_runtime_spec, :metadata}}
  defp exact_hash(hash, hash), do: :ok
  defp exact_hash(_claimed, _actual), do: {:error, :realized_contact_runtime_spec_hash_mismatch}
end
