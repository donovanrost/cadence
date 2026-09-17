defmodule Cadence.Runtime.MissionRuntimeSpec do
  @moduledoc """
  Exact, immutable input accepted by the mission data plane.

  The data plane owns this contract. Callers must provide the complete binding
  set selected by Control; runtime processes never resolve a mutable governed
  artifact from an id and version.
  """

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.SemanticRuntime.PlanDecoder

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
          mission_model_revision_id: binary(),
          mission_model_content_sha256: binary(),
          runtime_plans: %{required(atom()) => RuntimePlan.t()},
          source_runtime_bases: map() | nil,
          runtime_basis_sha256: binary(),
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
    :mission_model_revision_id,
    :mission_model_content_sha256,
    :runtime_plans,
    :runtime_basis_sha256,
    :activated_at
  ]
  defstruct @enforce_keys ++
              [
                activation_request_id: nil,
                organization_id: nil,
                source_runtime_bases: nil,
                metadata: %{}
              ]

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
         :ok <- validate_content_hash(attrs, content_sha256),
         {:ok, mission_model} <- fetch_mission_model(attrs),
         {:ok, source_bases} <- fetch_source_bases(attrs),
         runtime_basis_sha256 <- runtime_basis_sha256(content_sha256, mission_model, source_bases),
         :ok <- validate_runtime_basis_hash(attrs, runtime_basis_sha256) do
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
         mission_model_revision_id: mission_model.revision_id,
         mission_model_content_sha256: mission_model.content_sha256,
         runtime_plans: mission_model.plans,
         source_runtime_bases: source_bases,
         runtime_basis_sha256: runtime_basis_sha256,
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
    {spec.activation_id, spec.generation, spec.runtime_basis_sha256}
  end

  @doc "Selects the admitted source model before a runtime partition starts."
  def for_partition(%__MODULE__{source_runtime_bases: nil} = spec, _partition), do: {:ok, spec}

  def for_partition(%__MODULE__{} = spec, %Cadence.Runtime.PartitionKey{
        affinity: :source_endpoint,
        value: id
      }) do
    case Map.fetch(spec.source_runtime_bases, id) do
      {:ok, basis} ->
        {:ok,
         %{
           spec
           | mission_model_revision_id: basis.mission_model_revision_id,
             mission_model_content_sha256: basis.mission_model_content_sha256,
             runtime_plans: basis.runtime_plans
         }}

      :error ->
        {:error, :spacecraft_model_not_active}
    end
  end

  def for_partition(%__MODULE__{}, _), do: {:error, :spacecraft_model_partition_required}

  defp fetch_source_bases(%{source_runtime_bases: sources})
       when is_map(sources) and map_size(sources) in 1..1000 do
    Enum.reduce_while(sources, {:ok, %{}}, fn {source, basis}, {:ok, result} ->
      with true <- is_binary(source) and byte_size(source) in 1..255 and is_map(basis),
           {:ok, _model} <- fetch_mission_model(basis) do
        {:cont,
         {:ok,
          Map.put(
            result,
            source,
            Map.take(basis, [
              :mission_model_revision_id,
              :mission_model_content_sha256,
              :runtime_plans
            ])
          )}}
      else
        _ -> {:halt, {:error, {:invalid_mission_runtime_spec, :source_runtime_bases}}}
      end
    end)
  end

  defp fetch_source_bases(%{source_runtime_bases: sources}) when not is_nil(sources),
    do: {:error, {:invalid_mission_runtime_spec, :source_runtime_bases}}

  defp fetch_source_bases(_), do: {:ok, nil}

  defp runtime_basis_sha256(content, model, nil), do: runtime_basis_sha256(content, model)

  defp runtime_basis_sha256(content, _model, sources) do
    identities =
      Enum.map(sources, fn {source, basis} ->
        {source,
         runtime_basis_sha256(content, %{
           revision_id: basis.mission_model_revision_id,
           content_sha256: basis.mission_model_content_sha256,
           plans: basis.runtime_plans
         })}
      end)

    ContentHash.term_sha256({:spacecraft_models_v1, content, Enum.sort(identities)})
  end

  @spec runtime_basis_sha256(binary(), map()) :: binary()
  def runtime_basis_sha256(binding_set_content_sha256, mission_model) do
    plan_hashes =
      mission_model.plans
      |> Enum.map(fn {target, plan} -> {target, plan.content_sha256} end)
      |> Enum.sort()

    ContentHash.term_sha256({
      binding_set_content_sha256,
      mission_model.revision_id,
      mission_model.content_sha256,
      plan_hashes,
      PlanDecoder.registered_execution_basis(mission_model.plans)
    })
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

  defp fetch_mission_model(attrs) do
    fetch_mission_model(
      Map.get(attrs, :mission_model_revision_id),
      Map.get(attrs, :mission_model_content_sha256),
      Map.get(attrs, :runtime_plans, %{})
    )
  end

  defp fetch_mission_model(revision_id, _content_sha256, _plans)
       when not is_binary(revision_id) or revision_id == "",
       do: {:error, {:invalid_mission_runtime_spec, :mission_model_revision_id}}

  defp fetch_mission_model(_revision_id, content_sha256, _plans)
       when not is_binary(content_sha256) or content_sha256 == "",
       do: {:error, {:invalid_mission_runtime_spec, :mission_model_content_sha256}}

  defp fetch_mission_model(_revision_id, _content_sha256, plans) when not is_map(plans),
    do: {:error, {:invalid_mission_runtime_spec, :runtime_plans}}

  defp fetch_mission_model(revision_id, content_sha256, plans),
    do: validate_runtime_plans(revision_id, content_sha256, plans)

  defp validate_runtime_plans(revision_id, content_sha256, plans) do
    required_targets = MapSet.new([:telemetry, :algorithm, :monitoring, :command])

    valid? =
      MapSet.new(Map.keys(plans)) == required_targets and
        Enum.all?(plans, fn {target, plan} ->
          match?(%RuntimePlan{}, plan) and plan.target == target and plan.status == :ready and
            plan.mission_model_revision_id == revision_id and
            plan.mission_model_content_sha256 == content_sha256
        end)

    if valid? do
      case MissionModelPlanDecoder.validate(plans) do
        :ok -> {:ok, %{revision_id: revision_id, content_sha256: content_sha256, plans: plans}}
        {:error, reason} -> {:error, {:invalid_mission_runtime_spec, {:runtime_plans, reason}}}
      end
    else
      {:error, {:invalid_mission_runtime_spec, :runtime_plans}}
    end
  end

  defp validate_runtime_basis_hash(attrs, computed_hash) do
    case Map.get(attrs, :runtime_basis_sha256, computed_hash) do
      ^computed_hash -> :ok
      _other -> {:error, {:mission_runtime_spec_mismatch, :runtime_basis_sha256}}
    end
  end
end
