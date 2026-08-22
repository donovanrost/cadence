defmodule Cadence.Procedures.Events.ProcedureExecutionEvent do
  @moduledoc """
  Event emitted during procedure execution lifecycle changes.

  Execution events are broadcast via PubSub when:
  - A procedure execution starts
  - A procedure execution completes successfully
  - A procedure execution fails
  - A procedure execution is paused
  - A procedure execution is cancelled/aborted

  ## Event Structure

  - `id` - Unique event identifier
  - `event_type` - Type of lifecycle event
  - `execution_id` - The procedure execution ID
  - `procedure_id` - The procedure definition ID
  - `procedure_name` - Name of the procedure
  - `mission_id` - Mission this execution belongs to
  - `organization_id` - Organization ID
  - `target_id` - Optional target (spacecraft/entity) identifier
  - `status` - Current execution status
  - `previous_status` - Previous execution status (for transitions)
  - `triggered_by` - How the execution was triggered (:manual, :schedule, :event)
  - `triggered_by_user_id` - User who triggered (for manual)
  - `parameters` - Parameters passed to the execution
  - `error_message` - Error details (for failed executions)
  - `step_index` - Current step index
  - `started_at` - When execution started
  - `completed_at` - When execution completed
  - `timestamp` - When this event was created

  ## Event Types

  - `:started` - Execution has begun
  - `:completed` - Execution finished successfully
  - `:failed` - Execution failed with an error
  - `:paused` - Execution was paused
  - `:resumed` - Execution was resumed from pause
  - `:cancelled` - Execution was cancelled/aborted
  - `:step_started` - A step within the procedure started
  - `:step_completed` - A step within the procedure completed

  ## PubSub Topic

  Events are broadcast to: `mission:<mission_id>:procedures`

  ## Usage

      # Subscribe to procedure events
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:\#{mission_id}:procedures")

      # Handle events
      def handle_info({:procedure_event, %ProcedureExecutionEvent{} = event}, state) do
        Logger.info("Procedure \#{event.procedure_name}: \#{event.event_type}")
        {:noreply, state}
      end
  """

  @type event_type ::
          :started
          | :completed
          | :failed
          | :pausing
          | :paused
          | :resumed
          | :cancelled
          | :step_started
          | :step_completed

  @type trigger_type :: :manual | :schedule | :event

  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          id: String.t(),
          event_type: event_type(),
          execution_id: String.t(),
          procedure_id: String.t(),
          procedure_name: String.t() | nil,
          mission_id: String.t(),
          organization_id: String.t(),
          target_id: String.t() | nil,
          status: atom(),
          previous_status: atom() | nil,
          triggered_by: trigger_type(),
          triggered_by_user_id: String.t() | nil,
          parameters: map(),
          error_message: String.t() | nil,
          step_index: integer() | nil,
          step_info: map() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          timestamp: DateTime.t()
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :event_type,
    :execution_id,
    :procedure_id,
    :procedure_name,
    :mission_id,
    :organization_id,
    :target_id,
    :status,
    :previous_status,
    :triggered_by,
    :triggered_by_user_id,
    :parameters,
    :error_message,
    :step_index,
    :step_info,
    :started_at,
    :completed_at,
    :timestamp
  ]

  @doc """
  Creates a new ProcedureExecutionEvent.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      event_type: attrs[:event_type],
      execution_id: attrs[:execution_id],
      procedure_id: attrs[:procedure_id],
      procedure_name: attrs[:procedure_name],
      mission_id: attrs[:mission_id],
      organization_id: attrs[:organization_id],
      target_id: attrs[:target_id],
      status: attrs[:status],
      previous_status: attrs[:previous_status],
      triggered_by: attrs[:triggered_by] || :manual,
      triggered_by_user_id: attrs[:triggered_by_user_id],
      parameters: attrs[:parameters] || %{},
      error_message: attrs[:error_message],
      step_index: attrs[:step_index],
      step_info: attrs[:step_info],
      started_at: attrs[:started_at],
      completed_at: attrs[:completed_at],
      timestamp: attrs[:timestamp] || CadenceTime.now()
    }
  end

  @doc """
  Creates a started event from an execution record.
  """
  @spec started(map()) :: t()
  def started(execution) do
    new(%{
      event_type: :started,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: execution.status,
      triggered_by: execution.triggered_by,
      triggered_by_user_id: execution.triggered_by_user_id,
      parameters: execution.parameters,
      started_at: execution.started_at
    })
  end

  @doc """
  Creates a completed event from an execution record.
  """
  @spec completed(map()) :: t()
  def completed(execution) do
    new(%{
      event_type: :completed,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: :completed,
      previous_status: execution.status,
      triggered_by: execution.triggered_by,
      triggered_by_user_id: execution.triggered_by_user_id,
      parameters: execution.parameters,
      started_at: execution.started_at,
      completed_at: CadenceTime.now()
    })
  end

  @doc """
  Creates a failed event from an execution record.
  """
  @spec failed(map(), String.t() | nil) :: t()
  def failed(execution, error_message \\ nil) do
    new(%{
      event_type: :failed,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: :failed,
      previous_status: execution.status,
      triggered_by: execution.triggered_by,
      triggered_by_user_id: execution.triggered_by_user_id,
      parameters: execution.parameters,
      error_message: error_message || execution.error_message,
      step_index: execution.error_step_index,
      started_at: execution.started_at,
      completed_at: CadenceTime.now()
    })
  end

  @doc """
  Creates a pausing event from an execution record (pause requested, waiting for step to complete).
  """
  @spec pausing(map()) :: t()
  def pausing(execution) do
    new(%{
      event_type: :pausing,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: :pausing,
      previous_status: :running,
      triggered_by: execution.triggered_by,
      step_index: execution.current_step_index,
      started_at: execution.started_at
    })
  end

  @doc """
  Creates a paused event from an execution record.
  """
  @spec paused(map()) :: t()
  def paused(execution) do
    new(%{
      event_type: :paused,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: :paused,
      previous_status: execution.status,
      triggered_by: execution.triggered_by,
      step_index: execution.current_step_index,
      started_at: execution.started_at
    })
  end

  @doc """
  Creates a cancelled event from an execution record.
  """
  @spec cancelled(map()) :: t()
  def cancelled(execution) do
    new(%{
      event_type: :cancelled,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: :cancelled,
      previous_status: execution.status,
      triggered_by: execution.triggered_by,
      step_index: execution.current_step_index,
      started_at: execution.started_at,
      completed_at: CadenceTime.now()
    })
  end

  @doc """
  Creates a resumed event from an execution record.
  """
  @spec resumed(map()) :: t()
  def resumed(execution) do
    new(%{
      event_type: :resumed,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: :running,
      previous_status: :paused,
      triggered_by: execution.triggered_by,
      step_index: execution.current_step_index,
      started_at: execution.started_at
    })
  end

  @doc """
  Creates a step_started event.
  """
  @spec step_started(map(), integer(), map()) :: t()
  def step_started(execution, step_index, step_info) do
    new(%{
      event_type: :step_started,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: execution.status,
      triggered_by: execution.triggered_by,
      step_index: step_index,
      step_info: step_info
    })
  end

  @doc """
  Creates a step_completed event.
  """
  @spec step_completed(map(), integer(), map()) :: t()
  def step_completed(execution, step_index, step_info) do
    new(%{
      event_type: :step_completed,
      execution_id: execution.id,
      procedure_id: execution.procedure_id,
      procedure_name: safe_get_in(execution, [:procedure, :name]),
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      status: execution.status,
      triggered_by: execution.triggered_by,
      step_index: step_index,
      step_info: step_info
    })
  end

  @doc """
  Returns true if this is a terminal event (execution ended).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{event_type: type}) do
    type in [:completed, :failed, :cancelled]
  end

  @doc """
  Returns true if this event indicates success.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{event_type: :completed}), do: true
  def success?(_), do: false

  @doc """
  Returns true if this event indicates failure.
  """
  @spec failure?(t()) :: boolean()
  def failure?(%__MODULE__{event_type: :failed}), do: true
  def failure?(_), do: false

  @doc """
  Returns a human-readable description of the event.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = event) do
    proc_name = event.procedure_name || "Unknown procedure"

    describe_event(event, proc_name)
  end

  defp describe_event(%__MODULE__{event_type: :started}, proc_name) do
    "#{proc_name} execution started"
  end

  defp describe_event(%__MODULE__{event_type: :completed}, proc_name) do
    "#{proc_name} execution completed successfully"
  end

  defp describe_event(%__MODULE__{event_type: :failed} = event, proc_name) do
    error = if event.error_message, do: ": #{event.error_message}", else: ""
    "#{proc_name} execution failed#{error}"
  end

  defp describe_event(%__MODULE__{event_type: :paused} = event, proc_name) do
    "#{proc_name} execution paused at step #{event.step_index}"
  end

  defp describe_event(%__MODULE__{event_type: :resumed}, proc_name) do
    "#{proc_name} execution resumed"
  end

  defp describe_event(%__MODULE__{event_type: :cancelled}, proc_name) do
    "#{proc_name} execution cancelled"
  end

  defp describe_event(%__MODULE__{event_type: :step_started} = event, proc_name) do
    step_type = safe_get_in(event.step_info, [:type]) || "step"
    "#{proc_name} step #{event.step_index} (#{step_type}) started"
  end

  defp describe_event(%__MODULE__{event_type: :step_completed} = event, proc_name) do
    step_type = safe_get_in(event.step_info, [:type]) || "step"
    "#{proc_name} step #{event.step_index} (#{step_type}) completed"
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp safe_get_in(nil, _), do: nil
  defp safe_get_in(value, []), do: value

  defp safe_get_in(struct, [key | rest]) when is_struct(struct),
    do: safe_get_in(Map.get(struct, key), rest)

  defp safe_get_in(map, [key | rest]) when is_map(map),
    do: safe_get_in(Map.get(map, key), rest)
end
