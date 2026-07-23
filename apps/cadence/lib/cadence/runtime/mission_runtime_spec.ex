defmodule Cadence.Runtime.MissionRuntimeSpec do
  @moduledoc """
  Exact, immutable input accepted by the mission data plane.

  The data plane owns this contract. Callers must provide the complete binding
  set selected by Control; runtime processes never resolve a mutable governed
  artifact from an id and version.
  """

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Platform.ContentHash

  @type t :: %__MODULE__{
          activation_id: binary(),
          activation_request_id: binary() | nil,
          organization_id: binary() | nil,
          mission_id: binary(),
          generation: pos_integer(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          binding_set_content_sha256: binary(),
          binding_set: BindingSet.t(),
          activated_at: DateTime.t(),
          metadata: map()
        }

  @enforce_keys [
    :activation_id,
    :mission_id,
    :generation,
    :binding_set_id,
    :binding_set_version,
    :binding_set_content_sha256,
    :binding_set,
    :activated_at
  ]
  defstruct @enforce_keys ++ [activation_request_id: nil, organization_id: nil, metadata: %{}]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, activation_id} <- fetch_non_empty_binary(attrs, :activation_id),
         {:ok, mission_id} <- fetch_non_empty_binary(attrs, :mission_id),
         {:ok, generation} <- fetch_positive_integer(attrs, :generation),
         {:ok, binding_set_id} <- fetch_non_empty_binary(attrs, :binding_set_id),
         {:ok, binding_set_version} <- fetch_positive_integer(attrs, :binding_set_version),
         {:ok, %BindingSet{} = binding_set} <- fetch_binding_set(attrs),
         :ok <-
           validate_binding_set_scope(
             binding_set,
             mission_id,
             binding_set_id,
             binding_set_version
           ),
         :ok <- validate_organization_scope(binding_set, Map.get(attrs, :organization_id)),
         {:ok, %DateTime{} = activated_at} <- fetch_datetime(attrs, :activated_at),
         {:ok, metadata} <- fetch_metadata(attrs),
         content_sha256 <- content_sha256(binding_set),
         :ok <- validate_content_hash(attrs, content_sha256) do
      {:ok,
       %__MODULE__{
         activation_id: activation_id,
         activation_request_id: Map.get(attrs, :activation_request_id),
         organization_id: Map.get(attrs, :organization_id),
         mission_id: mission_id,
         generation: generation,
         binding_set_id: binding_set_id,
         binding_set_version: binding_set_version,
         binding_set_content_sha256: content_sha256,
         binding_set: binding_set,
         activated_at: activated_at,
         metadata: metadata
       }}
    end
  end

  @spec content_sha256(BindingSet.t()) :: binary()
  def content_sha256(%BindingSet{} = binding_set) do
    ContentHash.term_sha256(binding_set)
  end

  @spec identity(t()) :: {binary(), pos_integer(), binary()}
  def identity(%__MODULE__{} = spec) do
    {spec.activation_id, spec.generation, spec.binding_set_content_sha256}
  end

  defp fetch_non_empty_binary(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid_mission_runtime_spec, field}}
    end
  end

  defp fetch_positive_integer(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_integer(value) and value > 0 -> {:ok, value}
      _other -> {:error, {:invalid_mission_runtime_spec, field}}
    end
  end

  defp fetch_binding_set(attrs) do
    case Map.fetch(attrs, :binding_set) do
      {:ok, %BindingSet{} = binding_set} -> {:ok, binding_set}
      _other -> {:error, {:invalid_mission_runtime_spec, :binding_set}}
    end
  end

  defp fetch_datetime(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, %DateTime{} = datetime} -> {:ok, datetime}
      _other -> {:error, {:invalid_mission_runtime_spec, field}}
    end
  end

  defp fetch_metadata(attrs) do
    case Map.get(attrs, :metadata, %{}) do
      metadata when is_map(metadata) -> {:ok, metadata}
      _other -> {:error, {:invalid_mission_runtime_spec, :metadata}}
    end
  end

  defp validate_binding_set_scope(binding_set, mission_id, binding_set_id, binding_set_version) do
    if binding_set.mission_id == mission_id and binding_set.binding_set_id == binding_set_id and
         binding_set.version == binding_set_version do
      :ok
    else
      {:error, {:mission_runtime_spec_mismatch, :binding_set_identity}}
    end
  end

  defp validate_organization_scope(%BindingSet{organization_id: nil}, _organization_id), do: :ok
  defp validate_organization_scope(%BindingSet{}, nil), do: :ok

  defp validate_organization_scope(
         %BindingSet{organization_id: organization_id},
         organization_id
       ),
       do: :ok

  defp validate_organization_scope(%BindingSet{}, _organization_id),
    do: {:error, {:mission_runtime_spec_mismatch, :organization_id}}

  defp validate_content_hash(attrs, computed_hash) do
    case Map.get(attrs, :binding_set_content_sha256, computed_hash) do
      ^computed_hash -> :ok
      _other -> {:error, {:mission_runtime_spec_mismatch, :binding_set_content_sha256}}
    end
  end
end
