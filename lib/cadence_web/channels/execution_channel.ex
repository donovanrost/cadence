defmodule CadenceWeb.ExecutionChannel do
  @moduledoc """
  Channel for real-time procedure execution updates.

  Clients join with an execution ID and receive:
  - Current execution state immediately on join (catch-up)
  - Real-time step status updates as execution progresses
  - Log messages

  ## Topic Format

      "execution:<execution_id>"

  ## Outgoing Messages

  - `state` - Full current state (sent on join)
  - `step_started` - A step began executing
  - `step_completed` - A step finished successfully
  - `step_failed` - A step failed
  - `step_blocked` - A step was blocked by failed dependency
  - `step_skipped` - A step was skipped
  - `log` - Log message from execution
  - `status_changed` - Execution status changed
  """

  use CadenceWeb, :channel

  alias Cadence.Accounts
  alias Cadence.Missions
  alias Cadence.Missions.Policy
  alias Cadence.Procedures
  alias Cadence.Procedures.Events.StepEvent

  require Logger

  @impl true
  def join("execution:" <> execution_id, _payload, socket) do
    user_id = socket.assigns[:user_id]

    with {:ok, user} <- load_user(user_id),
         {:ok, execution} <- get_execution(execution_id),
         {:ok, mission} <- get_mission(execution.mission_id),
         :ok <- authorize_user(user, mission) do
      # Subscribe to PubSub for real-time updates
      Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution_id}")

      socket =
        socket
        |> assign(:execution_id, execution_id)
        |> assign(:execution, execution)
        # Track running steps locally to provide accurate state on late join
        |> assign(:running_steps, MapSet.new())

      # Send current state immediately
      send(self(), :send_current_state)

      {:ok, socket}
    else
      {:error, :user_not_found} ->
        {:error, %{reason: "unauthorized"}}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}

      {:error, :unauthorized} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  defp load_user(nil), do: {:error, :user_not_found}

  defp load_user(user_id) do
    try do
      user = Accounts.get_user!(user_id)
      {:ok, Cadence.Repo.preload(user, :organization_memberships)}
    rescue
      Ecto.NoResultsError -> {:error, :user_not_found}
    end
  end

  defp get_execution(execution_id) do
    case Procedures.get_execution(execution_id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  defp get_mission(mission_id) do
    case Missions.get_mission(mission_id) do
      nil -> {:error, :not_found}
      mission -> {:ok, mission}
    end
  end

  defp authorize_user(user, mission) do
    case Policy.authorize(:view, user, mission) do
      :ok -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  @impl true
  def handle_info(:send_current_state, socket) do
    execution = socket.assigns.execution
    execution_id = socket.assigns.execution_id

    # Derive current step state from outbox events (source of truth)
    # This ensures late-joining clients get accurate state even if they
    # missed real-time PubSub messages
    step_state = derive_step_state_from_events(execution_id)

    state = %{
      execution_id: execution.id,
      status: to_string(execution.status),
      running_steps: step_state.running,
      completed_steps: step_state.completed,
      failed_steps: step_state.failed,
      blocked_steps: step_state.blocked,
      skipped_steps: step_state.skipped,
      step_results: step_state.step_results,
      started_at: format_datetime(execution.started_at),
      completed_at: format_datetime(execution.completed_at)
    }

    push(socket, "state", state)

    # Initialize local running_steps from derived state for future updates
    {:noreply, assign(socket, :running_steps, MapSet.new(step_state.running))}
  end

  # Handle PubSub messages and forward to client

  @impl true
  def handle_info({:dag_step_started, step_name, data}, socket) do
    push(socket, "step_started", %{
      step: step_name,
      data: data,
      timestamp: System.system_time(:millisecond)
    })

    # Track running step locally
    running_steps = MapSet.put(socket.assigns.running_steps, step_name)
    {:noreply, assign(socket, :running_steps, running_steps)}
  end

  @impl true
  def handle_info({:dag_step_completed, step_name, data}, socket) do
    push(socket, "step_completed", %{
      step: step_name,
      data: serialize_data(data),
      timestamp: System.system_time(:millisecond)
    })

    # Remove from running steps
    running_steps = MapSet.delete(socket.assigns.running_steps, step_name)
    {:noreply, assign(socket, :running_steps, running_steps)}
  end

  @impl true
  def handle_info({:dag_step_failed, step_name, reason}, socket) do
    push(socket, "step_failed", %{
      step: step_name,
      reason: inspect(reason),
      timestamp: System.system_time(:millisecond)
    })

    # Remove from running steps
    running_steps = MapSet.delete(socket.assigns.running_steps, step_name)
    {:noreply, assign(socket, :running_steps, running_steps)}
  end

  @impl true
  def handle_info({:dag_step_blocked, step_name, data}, socket) do
    push(socket, "step_blocked", %{
      step: step_name,
      data: serialize_data(data),
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:dag_step_skipped, step_name, data}, socket) do
    push(socket, "step_skipped", %{
      step: step_name,
      data: serialize_data(data),
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:status_changed, new_status, execution}, socket) do
    push(socket, "status_changed", %{
      status: to_string(new_status),
      execution_id: execution.id,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, assign(socket, :execution, execution)}
  end

  @impl true
  def handle_info({:log, level, message}, socket) do
    push(socket, "log", %{
      level: to_string(level),
      message: message,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  # Private functions

  defp derive_step_state_from_events(execution_id) do
    # Query outbox events and derive current state
    # This is the authoritative source of step status
    events = StepEvent.list_for_execution(execution_id)
    StepEvent.derive_state(events)
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(dt), do: DateTime.to_iso8601(dt)

  defp serialize_data(nil), do: nil
  defp serialize_data(data) when is_map(data) do
    # Convert atoms to strings for JSON serialization
    Map.new(data, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), serialize_data(v)}
      {k, v} -> {k, serialize_data(v)}
    end)
  end
  defp serialize_data(data) when is_atom(data), do: Atom.to_string(data)
  defp serialize_data(data), do: data
end
