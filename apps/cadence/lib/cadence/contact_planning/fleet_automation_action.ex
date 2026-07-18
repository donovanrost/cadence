defmodule Cadence.ContactPlanning.FleetAutomationAction do
  @moduledoc "Durable exact-grant checkpoint for one unattended fleet workflow action."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @actions [:plan, :repair, :submit, :approve, :execute]
  @states [:running, :succeeded, :failed, :skipped]

  @type t :: %__MODULE__{
          fleet_automation_action_id: binary(),
          idempotency_key: binary(),
          organization_id: binary(),
          mission_id: binary(),
          automation_grant_id: binary(),
          automation_grant_content_sha256: binary(),
          service_identity_id: binary(),
          fleet_planning_run_id: binary(),
          contact_plan_id: binary() | nil,
          contact_plan_version: pos_integer() | nil,
          action: atom(),
          lifecycle_state: atom(),
          attempt_count: pos_integer(),
          evidence_document: map(),
          result_document: map(),
          error_document: map(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :fleet_automation_action_id,
    :idempotency_key,
    :organization_id,
    :mission_id,
    :automation_grant_id,
    :automation_grant_content_sha256,
    :service_identity_id,
    :fleet_planning_run_id,
    :contact_plan_id,
    :contact_plan_version,
    :action,
    :lifecycle_state,
    :attempt_count,
    :evidence_document,
    :result_document,
    :error_document,
    :started_at,
    :completed_at,
    :inserted_at,
    :updated_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      fleet_automation_action_id:
        value(attrs, :fleet_automation_action_id, Ids.new("fleet_automation_action")),
      idempotency_key: required(attrs, :idempotency_key),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      automation_grant_id: required(attrs, :automation_grant_id),
      automation_grant_content_sha256: required(attrs, :automation_grant_content_sha256),
      service_identity_id: required(attrs, :service_identity_id),
      fleet_planning_run_id: required(attrs, :fleet_planning_run_id),
      contact_plan_id: optional_string(value(attrs, :contact_plan_id)),
      contact_plan_version:
        optional_positive(value(attrs, :contact_plan_version), :contact_plan_version),
      action: atom(value(attrs, :action), @actions, :action),
      lifecycle_state: atom(value(attrs, :lifecycle_state, :running), @states, :lifecycle_state),
      attempt_count: positive(value(attrs, :attempt_count, 1), :attempt_count),
      evidence_document: document(value(attrs, :evidence_document, %{}), :evidence_document),
      result_document: document(value(attrs, :result_document, %{}), :result_document),
      error_document: document(value(attrs, :error_document, %{}), :error_document),
      started_at: datetime(value(attrs, :started_at), :started_at),
      completed_at: optional_datetime(value(attrs, :completed_at), :completed_at),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
    |> validate_plan_binding()
    |> validate_completion()
  end

  defp validate_plan_binding(action) do
    if is_nil(action.contact_plan_id) == is_nil(action.contact_plan_version),
      do: action,
      else: raise(ArgumentError, "automation action Plan id and version must be set together")
  end

  defp validate_completion(%__MODULE__{lifecycle_state: :running} = action) do
    if is_nil(action.completed_at),
      do: action,
      else: raise(ArgumentError, "running automation action cannot be complete")
  end

  defp validate_completion(%__MODULE__{} = action) do
    if action.completed_at,
      do: action,
      else: raise(ArgumentError, "terminal automation action requires completed_at")
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(item) when is_binary(item) and item != "", do: item
  defp optional_string(_item), do: raise(ArgumentError, "optional reference must be non-empty")

  defp optional_positive(nil, _field), do: nil
  defp optional_positive(value, _field) when is_integer(value) and value > 0, do: value
  defp optional_positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}")
  end

  defp atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}"
  end

  defp document(value, _field) when is_map(value), do: JsonDocument.encode(value)
  defp document(_value, field), do: raise(ArgumentError, "#{field} must be an object")
  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(value, field), do: datetime(value, field)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
