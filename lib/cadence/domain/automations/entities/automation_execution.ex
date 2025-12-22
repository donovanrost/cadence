defmodule Cadence.Domain.Automations.Entities.AutomationExecution do
  @moduledoc """
  Domain entity representing an automation execution record.

  Tracks when an automation was triggered, what event caused it,
  and the result of the action taken.

  This is a pure domain entity with no Ecto dependencies.
  """

  @type status :: :pending | :running | :completed | :failed | :skipped

  @type t :: %__MODULE__{
          id: String.t() | nil,
          status: status(),
          trigger_event: map(),
          action_result: map() | nil,
          error_message: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          idempotency_key: String.t() | nil,
          automation_id: String.t(),
          organization_id: String.t(),
          mission_id: String.t() | nil,
          procedure_execution_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:automation_id, :organization_id, :trigger_event]
  defstruct [
    :id,
    :trigger_event,
    :action_result,
    :error_message,
    :started_at,
    :completed_at,
    :idempotency_key,
    :automation_id,
    :organization_id,
    :mission_id,
    :procedure_execution_id,
    :created_at,
    :updated_at,
    status: :pending
  ]

  @doc """
  Creates a new execution record.

  ## Parameters

  - `attrs` - Map with required keys: `:automation_id`, `:organization_id`, `:trigger_event`

  ## Returns

  - `{:ok, execution}` - Valid execution created
  - `{:error, reason}` - Validation error
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    with {:ok, automation_id} <- validate_required(attrs, :automation_id),
         {:ok, organization_id} <- validate_required(attrs, :organization_id),
         {:ok, trigger_event} <- validate_trigger_event(attrs) do
      {:ok,
       %__MODULE__{
         id: Map.get(attrs, :id),
         status: Map.get(attrs, :status, :pending),
         trigger_event: trigger_event,
         action_result: Map.get(attrs, :action_result),
         error_message: Map.get(attrs, :error_message),
         started_at: Map.get(attrs, :started_at),
         completed_at: Map.get(attrs, :completed_at),
         idempotency_key: Map.get(attrs, :idempotency_key),
         automation_id: automation_id,
         organization_id: organization_id,
         mission_id: Map.get(attrs, :mission_id),
         procedure_execution_id: Map.get(attrs, :procedure_execution_id),
         created_at: Map.get(attrs, :created_at),
         updated_at: Map.get(attrs, :updated_at)
       }}
    end
  end

  @doc """
  Marks the execution as running.
  """
  @spec start(t()) :: {:ok, t()}
  def start(%__MODULE__{} = execution) do
    {:ok, %{execution | status: :running, started_at: DateTime.utc_now()}}
  end

  @doc """
  Marks the execution as completed with optional result.
  """
  @spec complete(t(), map() | nil) :: {:ok, t()}
  def complete(%__MODULE__{} = execution, result \\ nil) do
    {:ok,
     %{
       execution
       | status: :completed,
         action_result: result,
         completed_at: DateTime.utc_now()
     }}
  end

  @doc """
  Marks the execution as failed with an error message.
  """
  @spec fail(t(), String.t()) :: {:ok, t()}
  def fail(%__MODULE__{} = execution, error_message) do
    {:ok,
     %{
       execution
       | status: :failed,
         error_message: error_message,
         completed_at: DateTime.utc_now()
     }}
  end

  @doc """
  Marks the execution as skipped with an optional reason.
  """
  @spec skip(t(), String.t() | nil) :: {:ok, t()}
  def skip(%__MODULE__{} = execution, reason \\ nil) do
    {:ok,
     %{
       execution
       | status: :skipped,
         error_message: reason,
         completed_at: DateTime.utc_now()
     }}
  end

  @doc """
  Links the execution to a procedure execution.
  """
  @spec link_procedure_execution(t(), String.t()) :: {:ok, t()}
  def link_procedure_execution(%__MODULE__{} = execution, procedure_execution_id) do
    {:ok, %{execution | procedure_execution_id: procedure_execution_id}}
  end

  @doc """
  Updates the execution status and related fields.
  """
  @spec update_status(t(), map()) :: {:ok, t()}
  def update_status(%__MODULE__{} = execution, attrs) do
    updated =
      execution
      |> maybe_update(:status, attrs)
      |> maybe_update(:action_result, attrs)
      |> maybe_update(:error_message, attrs)
      |> maybe_update(:started_at, attrs)
      |> maybe_update(:completed_at, attrs)
      |> maybe_update(:procedure_execution_id, attrs)

    {:ok, updated}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:error, {:required, key}}
      "" -> {:error, {:required, key}}
      value -> {:ok, value}
    end
  end

  defp validate_trigger_event(attrs) do
    case Map.get(attrs, :trigger_event) do
      nil -> {:error, {:required, :trigger_event}}
      event when is_map(event) -> {:ok, event}
      _ -> {:error, {:invalid, :trigger_event}}
    end
  end

  defp maybe_update(execution, field, attrs) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> Map.put(execution, field, value)
      :error -> execution
    end
  end
end
