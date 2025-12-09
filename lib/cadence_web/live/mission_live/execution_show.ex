defmodule CadenceWeb.MissionLive.ExecutionShow do
  @moduledoc """
  LiveView for displaying procedure execution details and logs.

  Features:
  - Real-time log streaming via PubSub
  - Log level filtering
  - Execution status and controls (pause/resume/abort)
  - Step progress tracking
  """
  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.Dag.Validator
  alias Cadence.Procedures.Events.ProcedureExecutionEvent
  alias Cadence.Procedures.Events.StepEvent
  alias Cadence.Procedures.ProcedureLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission
    execution_id = params["execution_id"]
    procedure_id = params["procedure_id"]

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        execution = Procedures.get_execution!(execution_id)

        if execution.procedure_id == procedure_id and execution.mission_id == mission.id do
          # Subscribe to real-time updates
          if connected?(socket) do
            require Logger
            Logger.info("ExecutionShow subscribing to procedure:#{execution_id}")
            # Subscribe to execution-specific topic (logs, step events)
            Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution_id}")
            # Subscribe to mission procedures topic (status changes from coordinator)
            Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:procedures")
          end

          logs = Procedures.list_logs(execution_id, limit: 500)

          # Load version to check if DAG format
          version = Procedures.get_version!(execution.procedure_version_id)
          is_dag = Validator.is_dag_format?(version.source)
          dag_steps = if is_dag, do: version.source["steps"], else: %{}

          # Generate socket token for channel connection
          socket_token = generate_socket_token(socket.assigns.current_scope.user)

          {:noreply,
           socket
           |> assign(:page_title, "Execution Details")
           |> assign(:execution, execution)
           |> assign(:procedure, execution.procedure)
           |> assign(:logs, logs)
           |> assign(:auto_scroll, true)
           |> assign(:is_dag, is_dag)
           |> assign(:dag_steps, dag_steps)
           |> assign(:socket_token, socket_token)
           |> assign(:step_progress, %{})
           # Derive step state from outbox events (source of truth)
           |> assign_step_state_from_events(execution_id)
           # Clear running steps if execution is in terminal state
           # (no steps are actually running after abort/complete/fail)
           |> maybe_clear_running_steps(execution.status)}
        else
          {:noreply,
           socket
           |> put_flash(:error, "Execution not found")
           |> push_navigate(to: ~p"/missions/#{mission}/procedures")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this execution")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  @impl true
  def handle_info({:log, level, message}, socket) do
    # Real-time log from execution process
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      step_index: nil
    }

    {:noreply, update(socket, :logs, fn logs -> logs ++ [new_log] end)}
  end

  def handle_info({:status_changed, _new_status, execution}, socket) do
    # Update the execution state and sync step tracking from DB
    # This ensures the DAG visualization shows correct state on status changes
    {:noreply,
     socket
     |> assign(:execution, execution)
     |> assign(:completed_steps, execution.completed_steps || [])
     |> assign(:failed_steps, execution.failed_steps || [])
     |> assign(:blocked_steps, execution.blocked_steps || [])
     |> assign(:skipped_steps, execution.skipped_steps || [])
     |> assign(:timed_out_steps, Map.get(execution, :timed_out_steps, []))
     |> assign(:step_results, execution.step_results || %{})
     |> maybe_clear_running_steps(execution.status)}
  end

  # Handle procedure events from ExecutionCoordinator (via mission:*:procedures topic)
  def handle_info({:procedure_event, %ProcedureExecutionEvent{} = event}, socket) do
    # Only handle events for this execution
    if event.execution_id == socket.assigns.execution.id do
      # Reload the execution to get fresh data
      execution = Procedures.get_execution!(event.execution_id)

      {:noreply,
       socket
       |> assign(:execution, execution)
       # Sync step tracking from DB when execution updates (especially on completion)
       |> assign(:completed_steps, execution.completed_steps || [])
       |> assign(:failed_steps, execution.failed_steps || [])
       |> assign(:blocked_steps, execution.blocked_steps || [])
       |> assign(:skipped_steps, execution.skipped_steps || [])
       |> assign(:timed_out_steps, Map.get(execution, :timed_out_steps, []))
       |> assign(:step_results, execution.step_results || %{})
       # Clear running steps on terminal states
       |> maybe_clear_running_steps(execution.status)
       |> maybe_add_status_log(event.event_type)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:step_started, step_index, step}, socket) do
    step_type = Map.get(step, "type", "unknown")

    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :info,
      message: "Step #{step_index} started: #{step_type}",
      step_index: step_index
    }

    {:noreply, update(socket, :logs, fn logs -> logs ++ [new_log] end)}
  end

  def handle_info({:step_completed, step_index, step}, socket) do
    step_type = Map.get(step, "type", "unknown")

    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :info,
      message: "Step #{step_index} completed: #{step_type}",
      step_index: step_index
    }

    {:noreply, update(socket, :logs, fn logs -> logs ++ [new_log] end)}
  end

  def handle_info({:checkpoint, name}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :debug,
      message: "Checkpoint: #{name}",
      step_index: nil
    }

    {:noreply, update(socket, :logs, fn logs -> logs ++ [new_log] end)}
  end

  # DAG step status updates
  # Note: Logs are persisted and broadcast separately via {:log, ...} from ExecutionProcess
  # These handlers only update step tracking state
  def handle_info({:dag_step_started, step_name, _data}, socket) do
    {:noreply, update(socket, :running_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_info({:dag_step_completed, step_name, _data}, socket) do
    {:noreply,
     socket
     |> update(:running_steps, fn steps -> List.delete(steps, step_name) end)
     |> update(:completed_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_info({:dag_step_failed, step_name, _reason}, socket) do
    {:noreply,
     socket
     |> update(:running_steps, fn steps -> List.delete(steps, step_name) end)
     |> update(:failed_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_info({:dag_step_blocked, step_name, _data}, socket) do
    {:noreply, update(socket, :blocked_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_info({:dag_step_skipped, step_name, _data}, socket) do
    {:noreply, update(socket, :skipped_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_info({:dag_step_timed_out, step_name, _data}, socket) do
    {:noreply,
     socket
     |> update(:running_steps, fn steps -> List.delete(steps, step_name) end)
     |> update(:timed_out_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_info({:dag_step_progress, step_name, progress_data}, socket) do
    # Update step progress tracking and push to the DAG viewer hook
    {:noreply,
     socket
     |> update(:step_progress, fn progress -> Map.put(progress, step_name, progress_data) end)
     |> push_event("step_progress", %{
       step_name: step_name,
       progress: stringify_progress(progress_data)
     })}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Channel Event Handlers (from JS hook via pushEvent)
  # ============================================================================

  @impl true
  def handle_event("execution_state", state, socket) do
    # Initial state catch-up from channel
    require Logger
    Logger.info("ExecutionShow received execution_state from channel")

    {:noreply,
     socket
     |> assign(:running_steps, state["running_steps"] || [])
     |> assign(:completed_steps, state["completed_steps"] || [])
     |> assign(:failed_steps, state["failed_steps"] || [])
     |> assign(:blocked_steps, state["blocked_steps"] || [])
     |> assign(:skipped_steps, state["skipped_steps"] || [])
     |> assign(:step_results, state["step_results"] || %{})}
  end

  def handle_event("channel_step_started", %{"step" => step_name}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :info,
      message: "DAG step started: #{step_name}",
      step_index: nil
    }

    {:noreply,
     socket
     |> update(:logs, fn logs -> logs ++ [new_log] end)
     |> update(:running_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_event("channel_step_completed", %{"step" => step_name}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :info,
      message: "DAG step completed: #{step_name}",
      step_index: nil
    }

    {:noreply,
     socket
     |> update(:logs, fn logs -> logs ++ [new_log] end)
     |> update(:running_steps, fn steps -> List.delete(steps, step_name) end)
     |> update(:completed_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_event("channel_step_failed", %{"step" => step_name, "reason" => reason}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :error,
      message: "DAG step failed: #{step_name} - #{reason}",
      step_index: nil
    }

    {:noreply,
     socket
     |> update(:logs, fn logs -> logs ++ [new_log] end)
     |> update(:running_steps, fn steps -> List.delete(steps, step_name) end)
     |> update(:failed_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_event("channel_step_blocked", %{"step" => step_name}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :warn,
      message: "DAG step blocked: #{step_name}",
      step_index: nil
    }

    {:noreply,
     socket
     |> update(:logs, fn logs -> logs ++ [new_log] end)
     |> update(:blocked_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_event("channel_step_skipped", %{"step" => step_name}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :info,
      message: "DAG step skipped: #{step_name}",
      step_index: nil
    }

    {:noreply,
     socket
     |> update(:logs, fn logs -> logs ++ [new_log] end)
     |> update(:skipped_steps, fn steps -> [step_name | steps] end)}
  end

  def handle_event("channel_status_changed", %{"status" => status}, socket) do
    # Reload execution from DB to get updated data
    execution = Procedures.get_execution!(socket.assigns.execution.id)
    # Also update our local status in case DB hasn't persisted yet
    updated_execution = %{execution | status: String.to_existing_atom(status)}
    {:noreply, assign(socket, :execution, updated_execution)}
  end

  def handle_event("channel_log", %{"level" => level, "message" => message}, socket) do
    new_log = %ProcedureLog{
      id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: String.to_atom(level),
      message: message,
      step_index: nil
    }

    {:noreply, update(socket, :logs, fn logs -> logs ++ [new_log] end)}
  end

  @impl true
  def handle_event("toggle_auto_scroll", _, socket) do
    {:noreply, update(socket, :auto_scroll, &(!&1))}
  end

  def handle_event("pause", _, socket) do
    execution = socket.assigns.execution

    case Procedures.Engine.ExecutionCoordinator.pause(execution.mission_id, execution.id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Pause signal sent")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
    end
  end

  def handle_event("resume", _, socket) do
    execution = socket.assigns.execution

    case Procedures.Engine.ExecutionCoordinator.resume(execution.mission_id, execution.id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Resume signal sent")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
    end
  end

  def handle_event("abort", _, socket) do
    execution = socket.assigns.execution

    case Procedures.Engine.ExecutionCoordinator.abort(execution.mission_id, execution.id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Abort signal sent")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to abort: #{inspect(reason)}")}
    end
  end

  def handle_event("refresh_logs", _, socket) do
    logs = Procedures.list_logs(socket.assigns.execution.id, limit: 500)
    {:noreply, assign(socket, :logs, logs)}
  end

  def handle_event("rerun", _, socket) do
    execution = socket.assigns.execution
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :send_command, scope, mission) do
      :ok ->
        # Re-run with the same version and parameters
        case Procedures.Engine.ExecutionCoordinator.start_execution(
               mission.id,
               execution.procedure_id,
               version_id: execution.procedure_version_id,
               parameters: execution.parameters || %{},
               user_id: scope.user.id,
               triggered_by: :manual
             ) do
          {:ok, new_execution} ->
            {:noreply,
             socket
             |> put_flash(:info, "Procedure re-started")
             |> push_navigate(
               to:
                 ~p"/missions/#{mission}/procedures/#{execution.procedure_id}/executions/#{new_execution}"
             )}

          {:error, :at_concurrency_limit} ->
            {:noreply, put_flash(socket, :error, "Too many procedures running. Please wait.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to execute procedures")}
    end
  end

  def handle_event("retry_from_failure", _, socket) do
    execution = socket.assigns.execution
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :send_command, scope, mission) do
      :ok ->
        # Get completed steps from the failed execution
        completed_steps = execution.completed_steps || []

        # Start a new execution with the completed steps pre-loaded
        # The ExecutionProcess will derive state from outbox events,
        # so we need to copy the step events to the new execution
        case Procedures.Engine.ExecutionCoordinator.start_execution(
               mission.id,
               execution.procedure_id,
               version_id: execution.procedure_version_id,
               parameters: execution.parameters || %{},
               user_id: scope.user.id,
               triggered_by: :manual,
               resume_from_execution_id: execution.id
             ) do
          {:ok, new_execution} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Retrying from last successful step (#{length(completed_steps)} steps already complete)"
             )
             |> push_navigate(
               to:
                 ~p"/missions/#{mission}/procedures/#{execution.procedure_id}/executions/#{new_execution}"
             )}

          {:error, :at_concurrency_limit} ->
            {:noreply, put_flash(socket, :error, "Too many procedures running. Please wait.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to execute procedures")}
    end
  end

  defp maybe_add_status_log(socket, _status_or_event_type) do
    # Status logs are now persisted and broadcast by ExecutionProcess via {:log, ...}
    # messages, so we don't need to add them in-memory here anymore.
    # The {:log, ...} handler in handle_info already adds them to the UI.
    socket
  end

  defp maybe_clear_running_steps(socket, status)
       when status in [:completed, :failed, :cancelled] do
    # Clear running steps when execution reaches terminal state
    assign(socket, :running_steps, [])
  end

  defp maybe_clear_running_steps(socket, _status), do: socket

  defp normalize_level(level) when is_atom(level), do: level
  defp normalize_level("debug"), do: :debug
  defp normalize_level("info"), do: :info
  defp normalize_level("warn"), do: :warn
  defp normalize_level("error"), do: :error
  defp normalize_level(_), do: :info

  defp status_color(:pending), do: "bg-gray-100 text-gray-700"
  defp status_color(:running), do: "bg-blue-100 text-blue-700"
  defp status_color(:completed), do: "bg-green-100 text-green-700"
  defp status_color(:failed), do: "bg-red-100 text-red-700"
  defp status_color(:pausing), do: "bg-orange-100 text-orange-700"
  defp status_color(:paused), do: "bg-yellow-100 text-yellow-700"
  defp status_color(:cancelled), do: "bg-gray-100 text-gray-700"
  defp status_color(_), do: "bg-gray-100 text-gray-700"

  defp log_level_color(:debug), do: "text-gray-500"
  defp log_level_color(:info), do: "text-blue-600"
  defp log_level_color(:warn), do: "text-amber-600"
  defp log_level_color(:error), do: "text-red-600"
  defp log_level_color(_), do: "text-gray-600"

  # Row classes with subtle background and visible border for separation
  defp log_row_classes(:debug), do: "bg-white border-gray-200"
  defp log_row_classes(:info), do: "bg-blue-50/50 border-blue-100"
  defp log_row_classes(:warn), do: "bg-amber-50/50 border-amber-200"
  defp log_row_classes(:error), do: "bg-red-50/50 border-red-200"
  defp log_row_classes(_), do: "bg-white border-gray-200"

  defp format_level(:debug), do: "DEBUG"
  defp format_level(:info), do: "INFO"
  defp format_level(:warn), do: "WARN"
  defp format_level(:error), do: "ERROR"
  defp format_level(level), do: level

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S.%f")
    |> String.slice(0, 12)
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp terminal_status?(status), do: status in [:completed, :failed, :cancelled]

  defp has_completed_steps?(execution) do
    completed = execution.completed_steps || []
    length(completed) > 0
  end

  defp get_step_error(step_results, step_name) do
    case Map.get(step_results, step_name) do
      %{"error" => error} when is_binary(error) -> error
      %{error: error} when is_binary(error) -> error
      %{"error" => error} -> inspect(error)
      %{error: error} -> inspect(error)
      _ -> nil
    end
  end

  # Convert progress data to JSON-safe format (atoms to strings)
  defp stringify_progress(progress_data) when is_map(progress_data) do
    Map.new(progress_data, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_progress(v)}
      {k, v} -> {k, stringify_progress(v)}
    end)
  end

  defp stringify_progress(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify_progress(v), do: v

  defp generate_socket_token(user) do
    Phoenix.Token.sign(CadenceWeb.Endpoint, "user socket", user.id)
  end

  # Derives step state from outbox events and assigns to socket
  defp assign_step_state_from_events(socket, execution_id) do
    step_state = derive_step_state_from_events(execution_id)

    socket
    |> assign(:running_steps, step_state.running)
    |> assign(:completed_steps, step_state.completed)
    |> assign(:failed_steps, step_state.failed)
    |> assign(:blocked_steps, step_state.blocked)
    |> assign(:skipped_steps, step_state.skipped)
    |> assign(:timed_out_steps, Map.get(step_state, :timed_out, []))
    |> assign(:step_results, step_state.step_results)
  end

  defp derive_step_state_from_events(execution_id) do
    events = StepEvent.list_for_execution(execution_id)
    StepEvent.derive_state(events)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- ExecutionChannel hook for real-time updates -->
    <div
      id="execution-channel"
      phx-hook="ExecutionChannel"
      data-execution-id={@execution.id}
      data-socket-token={@socket_token}
      class="hidden"
    />

    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <.link
            navigate={~p"/missions/#{@mission}/procedures/#{@procedure}"}
            class="text-sm text-gray-500 hover:text-gray-700 flex items-center gap-1"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to {@procedure.name}
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-gray-900">Execution Details</h1>
          <p class="text-sm text-gray-500 font-mono">{@execution.id}</p>
        </div>

        <div class="flex items-center gap-2">
          <%= if @execution.status == :running do %>
            <.button phx-click="pause" class="btn-secondary">
              <.icon name="hero-pause" class="h-4 w-4 mr-1" /> Pause
            </.button>
            <.button
              phx-click="abort"
              class="btn-danger"
              data-confirm="Are you sure you want to abort this execution?"
            >
              <.icon name="hero-stop" class="h-4 w-4 mr-1" /> Abort
            </.button>
          <% end %>
          <%= if @execution.status == :pausing do %>
            <span class="inline-flex items-center px-3 py-2 text-sm text-orange-700 bg-orange-100 rounded animate-pulse">
              <.icon name="hero-pause" class="h-4 w-4 mr-1" /> Pausing...
            </span>
            <.button
              phx-click="abort"
              class="btn-danger"
              data-confirm="Are you sure you want to abort this execution?"
            >
              <.icon name="hero-stop" class="h-4 w-4 mr-1" /> Abort
            </.button>
          <% end %>
          <%= if @execution.status == :paused do %>
            <.button phx-click="resume" class="btn-primary">
              <.icon name="hero-play" class="h-4 w-4 mr-1" /> Resume
            </.button>
            <.button
              phx-click="abort"
              class="btn-danger"
              data-confirm="Are you sure you want to abort this execution?"
            >
              <.icon name="hero-stop" class="h-4 w-4 mr-1" /> Abort
            </.button>
          <% end %>
          <%= if terminal_status?(@execution.status) do %>
            <%= if @execution.status == :failed and has_completed_steps?(@execution) do %>
              <.button
                phx-click="retry_from_failure"
                class="btn-warning"
                title="Resume from where the previous execution failed, skipping already completed steps"
              >
                <.icon name="hero-forward" class="h-4 w-4 mr-1" /> Retry from failure
              </.button>
            <% end %>
            <.button
              phx-click="rerun"
              class={if @execution.status == :failed, do: "btn-secondary", else: "btn-primary"}
            >
              <.icon name="hero-arrow-path" class="h-4 w-4 mr-1" />
              {if @execution.status == :failed, do: "Re-run from start", else: "Re-run"}
            </.button>
          <% end %>
        </div>
      </div>
      
    <!-- Status Card -->
      <div class="bg-white shadow rounded-lg p-6">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-6">
          <div>
            <dt class="text-sm font-medium text-gray-500">Status</dt>
            <dd class="mt-1">
              <span class={[
                "inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-medium",
                status_color(@execution.status),
                @execution.status == :pausing && "animate-pulse"
              ]}>
                {Phoenix.Naming.humanize(@execution.status)}
              </span>
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Procedure</dt>
            <dd class="mt-1 text-sm text-gray-900">{@procedure.name}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Triggered By</dt>
            <dd class="mt-1 text-sm text-gray-900">
              {Phoenix.Naming.humanize(@execution.triggered_by)}
            </dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Current Step</dt>
            <dd class="mt-1 text-sm text-gray-900">{@execution.current_step_index || 0}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Started At</dt>
            <dd class="mt-1 text-sm text-gray-900">{format_datetime(@execution.started_at)}</dd>
          </div>
          <div>
            <dt class="text-sm font-medium text-gray-500">Completed At</dt>
            <dd class="mt-1 text-sm text-gray-900">{format_datetime(@execution.completed_at)}</dd>
          </div>
          <%= if @execution.error_message do %>
            <div class="col-span-2">
              <dt class="text-sm font-medium text-gray-500">Error</dt>
              <dd class="mt-1 text-sm text-red-600">{@execution.error_message}</dd>
            </div>
          <% end %>
        </div>

        <%= if @execution.parameters && map_size(@execution.parameters) > 0 do %>
          <div class="mt-4 pt-4 border-t">
            <dt class="text-sm font-medium text-gray-500 mb-2">Parameters</dt>
            <dd class="text-sm text-gray-900 font-mono bg-gray-50 p-2 rounded">
              {Jason.encode!(@execution.parameters, pretty: true)}
            </dd>
          </div>
        <% end %>
      </div>
      
    <!-- Failure Summary (for failed DAG executions) -->
      <%= if @execution.status == :failed and @is_dag and (length(@failed_steps) > 0 or length(@timed_out_steps) > 0) do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <div class="flex items-start gap-3">
            <div class="flex-shrink-0">
              <.icon name="hero-exclamation-triangle" class="h-6 w-6 text-red-600" />
            </div>
            <div class="flex-1">
              <h3 class="text-sm font-medium text-red-800">Execution Failed</h3>
              <div class="mt-2 text-sm text-red-700">
                <%= if length(@failed_steps) > 0 do %>
                  <div class="mb-2">
                    <span class="font-medium">Failed steps:</span>
                    <div class="flex flex-wrap gap-1 mt-1">
                      <%= for step <- @failed_steps do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                          {step}
                          <%= if error = get_step_error(@step_results, step) do %>
                            <span class="ml-1 text-red-600" title={error}>
                              <.icon name="hero-information-circle" class="h-3 w-3" />
                            </span>
                          <% end %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                <%= if length(@timed_out_steps) > 0 do %>
                  <div class="mb-2">
                    <span class="font-medium">Timed out steps:</span>
                    <div class="flex flex-wrap gap-1 mt-1">
                      <%= for step <- @timed_out_steps do %>
                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-orange-100 text-orange-800">
                          <.icon name="hero-clock" class="h-3 w-3 mr-1" />
                          {step}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                <%= if length(@blocked_steps) > 0 do %>
                  <div class="text-gray-600">
                    <span class="font-medium">{length(@blocked_steps)} steps blocked</span>
                    due to dependency failures
                  </div>
                <% end %>
              </div>
              <%= if has_completed_steps?(@execution) do %>
                <div class="mt-3 text-sm text-green-700">
                  <.icon name="hero-check-circle" class="h-4 w-4 inline" />
                  {length(@completed_steps)} steps completed successfully and can be skipped on retry.
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
      
    <!-- DAG Visualization (for DAG procedures) -->
      <%= if @is_dag do %>
        <div class="bg-white shadow rounded-lg overflow-hidden" style="height: 500px;">
          <%!-- Outer wrapper updates data attributes, inner div is phx-update="ignore" for hook content --%>
          <div
            id="dag-viewer-data"
            phx-hook="DagViewer"
            data-steps={Jason.encode!(@dag_steps)}
            data-step-results={Jason.encode!(@step_results)}
            data-step-progress={Jason.encode!(@step_progress)}
            data-completed-steps={Jason.encode!(@completed_steps)}
            data-failed-steps={Jason.encode!(@failed_steps)}
            data-blocked-steps={Jason.encode!(@blocked_steps)}
            data-skipped-steps={Jason.encode!(@skipped_steps)}
            data-timed-out-steps={Jason.encode!(@timed_out_steps)}
            data-running-steps={Jason.encode!(@running_steps)}
            data-execution-status={@execution.status}
            class="h-full"
          >
            <div id="dag-viewer-content" phx-update="ignore" class="h-full"></div>
          </div>
        </div>
      <% end %>
      
    <!-- Logs Section -->
      <div id="log-section" class="bg-white shadow rounded-lg" phx-hook="LogFilter">
        <div class="px-6 py-4 border-b flex items-center justify-between">
          <h2 class="text-lg font-medium text-gray-900">Execution Logs</h2>

          <div class="flex items-center gap-4">
            <!-- Log Level Filter -->
            <div class="flex items-center gap-2">
              <label class="text-sm text-gray-500">Filter:</label>
              <select
                data-log-filter-select
                class="text-sm border-gray-300 rounded-md shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              >
                <option value="all">All Levels</option>
                <option value="debug">Debug</option>
                <option value="info">Info</option>
                <option value="warn">Warning</option>
                <option value="error">Error</option>
              </select>
            </div>
            
    <!-- Auto-scroll toggle -->
            <button
              type="button"
              phx-click="toggle_auto_scroll"
              class={[
                "text-sm px-2 py-1 rounded",
                @auto_scroll && "bg-indigo-100 text-indigo-700",
                !@auto_scroll && "bg-gray-100 text-gray-600"
              ]}
            >
              Auto-scroll: {if @auto_scroll, do: "On", else: "Off"}
            </button>
            
    <!-- Refresh button for terminal states -->
            <%= if terminal_status?(@execution.status) do %>
              <button
                type="button"
                phx-click="refresh_logs"
                class="text-sm px-2 py-1 rounded bg-gray-100 text-gray-600 hover:bg-gray-200"
              >
                <.icon name="hero-arrow-path" class="h-4 w-4" />
              </button>
            <% end %>
          </div>
        </div>
        
    <!-- Log entries -->
        <div
          id="log-container"
          data-log-container
          class="max-h-[600px] overflow-y-auto font-mono text-xs"
          phx-hook="AutoScroll"
          data-auto-scroll={to_string(@auto_scroll)}
        >
          <%= if Enum.empty?(@logs) do %>
            <div class="p-8 text-center text-gray-500">
              <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-gray-400" />
              <p class="mt-2">No logs yet</p>
              <%= if not terminal_status?(@execution.status) do %>
                <p class="text-sm">Logs will appear here as the procedure executes.</p>
              <% end %>
            </div>
          <% else %>
            <div class="divide-y divide-gray-200">
              <%= for log <- @logs do %>
                <% level = normalize_level(log.level) %>
                <div data-log-level={level} class={["flex gap-3 px-2 py-1.5", log_row_classes(level)]}>
                  <div class="flex-shrink-0 w-20 text-gray-400">
                    <div class="text-[11px] tabular-nums">{format_timestamp(log.timestamp)}</div>
                    <div class="flex items-center gap-1.5 mt-0.5">
                      <span class={["font-semibold text-[10px]", log_level_color(level)]}>
                        {format_level(level)}
                      </span>
                      <%= if log.step_index do %>
                        <span class="text-[10px] text-gray-400">Step {log.step_index}</span>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex-1 text-gray-900 whitespace-pre-wrap break-words min-w-0">
                    {log.message}
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="px-6 py-3 border-t bg-gray-50 text-sm text-gray-500" data-log-count>
          {length(@logs)} log entries
        </div>
      </div>
    </div>
    """
  end
end
