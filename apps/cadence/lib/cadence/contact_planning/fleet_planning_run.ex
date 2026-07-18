defmodule Cadence.ContactPlanning.FleetPlanningRun do
  @moduledoc "Durable mission-scale planning orchestration and checkpoint state."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @states [:queued, :running, :completed, :partial, :failed, :canceled]
  @phases [
    :queued,
    :materializing,
    :searching,
    :optimizing,
    :materializing_plan,
    :finished
  ]
  @triggers [:manual, :scheduled, :repair]

  @type lifecycle_state :: :queued | :running | :completed | :partial | :failed | :canceled
  @type phase ::
          :queued
          | :materializing
          | :searching
          | :optimizing
          | :materializing_plan
          | :finished
  @type trigger_kind :: :manual | :scheduled | :repair

  @type t :: %__MODULE__{
          fleet_planning_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          lifecycle_state: lifecycle_state(),
          phase: phase(),
          trigger_kind: trigger_kind(),
          fleet_planning_policy_id: binary(),
          fleet_planning_policy_version: pos_integer(),
          algorithm_key: binary(),
          algorithm_version: pos_integer(),
          horizon_start: DateTime.t(),
          horizon_end: DateTime.t(),
          source_fleet_planning_run_id: binary() | nil,
          source_contact_plan_id: binary() | nil,
          source_contact_plan_version: pos_integer() | nil,
          candidate_contact_plan_id: binary() | nil,
          candidate_contact_plan_version: pos_integer() | nil,
          input_document: map(),
          progress_document: map(),
          result_summary_document: map(),
          failure_document: map(),
          trigger_actor_document: map(),
          triggered_by: binary(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :fleet_planning_run_id,
    :organization_id,
    :mission_id,
    :lifecycle_state,
    :phase,
    :trigger_kind,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :algorithm_key,
    :algorithm_version,
    :horizon_start,
    :horizon_end,
    :source_fleet_planning_run_id,
    :source_contact_plan_id,
    :source_contact_plan_version,
    :candidate_contact_plan_id,
    :candidate_contact_plan_version,
    :input_document,
    :progress_document,
    :result_summary_document,
    :failure_document,
    :trigger_actor_document,
    :triggered_by,
    :started_at,
    :completed_at,
    :inserted_at,
    :updated_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      fleet_planning_run_id: value(attrs, :fleet_planning_run_id, Ids.new("fleet_planning_run")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      lifecycle_state:
        attrs
        |> value(:lifecycle_state, :queued)
        |> atom(@states, :lifecycle_state),
      phase:
        attrs
        |> value(:phase, :queued)
        |> atom(@phases, :phase),
      trigger_kind:
        attrs
        |> value(:trigger_kind, :manual)
        |> atom(@triggers, :trigger_kind),
      fleet_planning_policy_id: required(attrs, :fleet_planning_policy_id),
      fleet_planning_policy_version:
        positive(value(attrs, :fleet_planning_policy_version), :fleet_planning_policy_version),
      algorithm_key: required(attrs, :algorithm_key),
      algorithm_version: positive(value(attrs, :algorithm_version), :algorithm_version),
      horizon_start: datetime(value(attrs, :horizon_start), :horizon_start),
      horizon_end: datetime(value(attrs, :horizon_end), :horizon_end),
      source_fleet_planning_run_id: optional_string(value(attrs, :source_fleet_planning_run_id)),
      source_contact_plan_id: optional_string(value(attrs, :source_contact_plan_id)),
      source_contact_plan_version:
        optional_positive(
          value(attrs, :source_contact_plan_version),
          :source_contact_plan_version
        ),
      candidate_contact_plan_id: optional_string(value(attrs, :candidate_contact_plan_id)),
      candidate_contact_plan_version:
        optional_positive(
          value(attrs, :candidate_contact_plan_version),
          :candidate_contact_plan_version
        ),
      input_document: document(value(attrs, :input_document, %{}), :input_document),
      progress_document: document(value(attrs, :progress_document, %{}), :progress_document),
      result_summary_document:
        document(value(attrs, :result_summary_document, %{}), :result_summary_document),
      failure_document: document(value(attrs, :failure_document, %{}), :failure_document),
      trigger_actor_document:
        document(value(attrs, :trigger_actor_document), :trigger_actor_document),
      triggered_by: required(attrs, :triggered_by),
      started_at: optional_datetime(value(attrs, :started_at), :started_at),
      completed_at: optional_datetime(value(attrs, :completed_at), :completed_at),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
    |> validate_horizon()
    |> validate_source_binding()
    |> validate_candidate_binding()
  end

  defp validate_horizon(run) do
    if DateTime.before?(run.horizon_start, run.horizon_end),
      do: run,
      else: raise(ArgumentError, "fleet planning horizon_end must be after horizon_start")
  end

  defp validate_source_binding(%__MODULE__{trigger_kind: :repair} = run) do
    if run.source_fleet_planning_run_id && run.source_contact_plan_id &&
         run.source_contact_plan_version do
      run
    else
      raise ArgumentError, "repair run requires source run and exact Plan version"
    end
  end

  defp validate_source_binding(run), do: run

  defp validate_candidate_binding(run) do
    if is_nil(run.candidate_contact_plan_id) ==
         is_nil(run.candidate_contact_plan_version) do
      run
    else
      raise ArgumentError, "candidate Plan id and version must be set together"
    end
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: raise(ArgumentError, "optional reference must be non-empty")

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")
  defp optional_positive(nil, _field), do: nil
  defp optional_positive(value, field), do: positive(value, field)

  defp atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp atom(value, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(value, field), do: datetime(value, field)

  defp document(value, _field) when is_map(value), do: JsonDocument.encode(value)
  defp document(_value, field), do: raise(ArgumentError, "#{field} must be an object")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
