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
  alias Cadence.Runtime.BindingSetIndex
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.Runtime.PartitionMetadata
  alias Cadence.Runtime.SourceRuntimeBases
  alias Cadence.SemanticRuntime.PlanDecoder
  alias Cadence.SemanticRuntime.RegisteredRegistry

  @type t :: %__MODULE__{
          activation_id: binary(),
          activation_request_id: binary() | nil,
          organization_id: binary() | nil,
          mission_id: binary(),
          generation: pos_integer(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          binding_set_content_sha256: binary(),
          binding_set: BindingSet.t() | BindingSetIndex.t(),
          mission_model_revision_id: binary(),
          mission_model_content_sha256: binary(),
          runtime_plans: %{required(atom()) => RuntimePlan.t()},
          source_runtime_bases: SourceRuntimeBases.t() | nil,
          runtime_basis_sha256: binary(),
          registered_execution_basis: [map()] | nil,
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
                registered_execution_basis: nil,
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
         {runtime_basis_sha256, execution_basis} <-
           runtime_basis(
             content_sha256,
             mission_model,
             source_bases,
             RegisteredRegistry.configured()
           ),
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
         registered_execution_basis:
           execution_basis |> Enum.map(&Map.delete(&1, :algorithm_id)) |> Enum.uniq(),
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

  @doc "Small reconciliation guard captured from the same executable basis as the runtime hash."
  def reconciliation_guard(%__MODULE__{registered_execution_basis: nil}), do: nil

  def reconciliation_guard(%__MODULE__{} = spec) do
    %{identity: identity(spec), execution_basis: spec.registered_execution_basis}
  end

  @doc "Checks for registered code or authorization changes without rebuilding configuration."
  def reconciliation_guard_current?(%{execution_basis: basis}),
    do: PlanDecoder.registered_execution_basis_current?(basis)

  def reconciliation_guard_current?(nil), do: false

  @doc "Selects the admitted source model before a runtime partition starts."
  def for_partition(%__MODULE__{source_runtime_bases: nil} = spec, _partition), do: {:ok, spec}

  def for_partition(%__MODULE__{} = spec, %Cadence.Runtime.PartitionKey{
        affinity: :source_endpoint,
        value: id
      }) do
    case SourceRuntimeBases.fetch(spec.source_runtime_bases, id) do
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

  @doc "Normalizes legacy specifications before they cross a process boundary."
  def compact_source_models(%__MODULE__{source_runtime_bases: nil} = spec), do: spec

  def compact_source_models(%__MODULE__{source_runtime_bases: %SourceRuntimeBases{}} = spec),
    do: spec

  def compact_source_models(%__MODULE__{} = spec) do
    {:ok, index} = SourceRuntimeBases.new(spec.source_runtime_bases)
    %{spec | source_runtime_bases: index}
  end

  @doc "Normalizes admitted configuration before copying it into mission process state."
  def compact(%__MODULE__{} = spec) do
    %{compact_source_models(spec) | binding_set: BindingSetIndex.new(spec.binding_set)}
  end

  @doc "Restores the exact admitted binding value for explicit inspection and replay."
  def expand(%__MODULE__{} = spec) do
    %{spec | binding_set: BindingSetIndex.materialize(spec.binding_set)}
  end

  @doc "Returns generation identity without copying fleet configuration or executable plans."
  def summary(%__MODULE__{} = spec) do
    Map.take(spec, [
      :activation_request_id,
      :activation_id,
      :generation,
      :binding_set_id,
      :binding_set_version,
      :binding_set_content_sha256,
      :runtime_basis_sha256
    ])
  end

  @doc "Keeps only the selected model in a partition's private execution state."
  def execution_input(%__MODULE__{} = spec, partition) do
    with {:ok, selected} <- for_partition(spec, partition) do
      {:ok, %{selected | source_runtime_bases: nil}}
    end
  end

  @doc "Identifies monitoring observations without copying executable plans into every result."
  def observation_context(%__MODULE__{} = spec) do
    monitoring_plan = Map.get(spec.runtime_plans, :monitoring)

    %{
      organization_id: spec.organization_id,
      mission_id: spec.mission_id,
      mission_model_revision_id: spec.mission_model_revision_id,
      runtime_plan_id: if(monitoring_plan, do: monitoring_plan.plan_id)
    }
  end

  @doc "Projects an admitted specification before copying it to a partition process."
  def partition_input(%__MODULE__{} = spec, %Cadence.Runtime.PartitionKey{} = partition) do
    with {:ok, selected} <- for_partition(spec, partition) do
      source_bases =
        if selected.source_runtime_bases,
          do: SourceRuntimeBases.take(selected.source_runtime_bases, [partition.value])

      {:ok,
       %{
         selected
         | binding_set: BindingSetIndex.select(selected.binding_set, partition),
           metadata: PartitionMetadata.project(selected.metadata, partition),
           source_runtime_bases: source_bases
       }}
    end
  end

  defp fetch_source_bases(%{source_runtime_bases: sources}) when not is_nil(sources) do
    with {:ok, index} <- SourceRuntimeBases.new(sources),
         true <-
           Enum.all?(index.models, fn {_key, basis} ->
             match?({:ok, _}, fetch_mission_model(basis))
           end) do
      {:ok, index}
    else
      _ -> {:error, {:invalid_mission_runtime_spec, :source_runtime_bases}}
    end
  end

  defp fetch_source_bases(_), do: {:ok, nil}

  defp runtime_basis(content, model, nil, registry) do
    basis = PlanDecoder.registered_execution_basis(model.plans, registry)
    {runtime_basis_hash(content, model, basis), basis}
  end

  defp runtime_basis(content, _model, %SourceRuntimeBases{} = index, registry) do
    models =
      Map.new(index.models, fn {key, basis} ->
        {key,
         runtime_basis(
           content,
           %{
             revision_id: basis.mission_model_revision_id,
             content_sha256: basis.mission_model_content_sha256,
             plans: basis.runtime_plans
           },
           nil,
           registry
         )}
      end)

    identities =
      Enum.map(index.sources, fn {source, key} -> {source, elem(Map.fetch!(models, key), 0)} end)

    execution_basis = models |> Enum.flat_map(fn {_, {_, basis}} -> basis end) |> Enum.uniq()

    {ContentHash.term_sha256({:spacecraft_models_v1, content, Enum.sort(identities)}),
     execution_basis}
  end

  @spec runtime_basis_sha256(binary(), map()) :: binary()
  def runtime_basis_sha256(binding_set_content_sha256, mission_model) do
    runtime_basis_hash(
      binding_set_content_sha256,
      mission_model,
      PlanDecoder.registered_execution_basis(mission_model.plans)
    )
  end

  defp runtime_basis_hash(binding_set_content_sha256, mission_model, execution_basis) do
    plan_hashes =
      mission_model.plans
      |> Enum.map(fn {target, plan} -> {target, plan.content_sha256} end)
      |> Enum.sort()

    ContentHash.term_sha256({
      binding_set_content_sha256,
      mission_model.revision_id,
      mission_model.content_sha256,
      plan_hashes,
      execution_basis
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
