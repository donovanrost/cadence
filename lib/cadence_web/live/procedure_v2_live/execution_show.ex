defmodule CadenceWeb.ProcedureV2Live.ExecutionShow do
  @moduledoc """
  LiveView for displaying and interacting with V2 procedure executions.

  Provides a two-column layout (Epsilon3-style):
  - Left: Navigation sidebar with timeline and step badges (A1, B2...)
  - Center: Full procedure document with all sections/steps visible

  Activity (signoffs, comments) is shown inline within each step card.
  """
  use CadenceWeb, :live_view

  alias Cadence.Outbox
  alias Cadence.Procedures
  alias Cadence.Procedures.BlockExecution
  alias Cadence.Procedures.V2
  alias Cadence.Procedures.V2.ExecutionProcess
  alias Cadence.Procedures.V2.ExecutionQueries
  # ExecutionProcess is now accessed via V2 context, but we still need
  # ExecutionProcess.start_or_attach for starting the process on mount

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:show_comment_form, false)
     |> assign(:step_comments, [])
     |> assign(:suggested_edits, [])
     |> assign(:suggesting_step_id, nil)
     |> assign(:allow_suggested_edits, true)
     |> assign(:comment_form, to_form(%{}, as: :comment))
     |> assign(:suggested_edit_form, to_form(%{}, as: :suggested_edit))
     # State for full document view
     |> assign(:expanded_step_ids, MapSet.new())
     |> assign(:collapsed_section_ids, MapSet.new())
     |> assign(:hidden_activity_step_ids, MapSet.new())
     |> assign(:visible_step_id, nil)
     |> assign(:commenting_step_id, nil)
     # ExecutionProcess state
     |> assign(:execution_process, nil)
     |> assign(:automation_running, false)
     |> assign(:automation_block_id, nil)
     |> assign(:automation_status, nil)
     # Command lifecycle timeline state
     |> assign(:command_lifecycles, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :show_execution, %{
         "procedure_id" => procedure_id,
         "execution_id" => execution_id
       }) do
    mission = socket.assigns.mission

    case load_execution_state(mission, procedure_id, execution_id) do
      {:ok, procedure, execution} ->
        socket
        |> maybe_subscribe_execution(execution, execution_id)
        |> assign_execution_state(procedure, execution, execution_id)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Execution not found")
        |> push_navigate(to: ~p"/missions/#{socket.assigns.mission}/procedures")
    end
  end

  defp load_execution_state(mission, procedure_id, execution_id) do
    with %{} = execution <- V2.get_execution_with_steps(execution_id),
         true <- execution.procedure_id == procedure_id,
         %Cadence.Procedures.Procedure{} = procedure <- Procedures.get_procedure(procedure_id),
         true <- procedure.mission_id == mission.id,
         true <- execution.mission_id == mission.id do
      {:ok, procedure, execution}
    else
      _ -> {:error, :not_found}
    end
  end

  defp maybe_subscribe_execution(socket, execution, execution_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "execution:#{execution_id}")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution_id}")
      Outbox.subscribe_mission(execution.mission_id)
    end

    socket
  end

  defp assign_execution_state(socket, procedure, execution, execution_id) do
    steps_by_section = group_steps_by_section(execution.step_executions)
    active_step = find_active_step(execution.step_executions)
    active_step_id = active_step && active_step.id
    command_lifecycles = build_initial_command_lifecycles(execution)
    step_comments = V2.list_comments(execution.id)
    suggested_edits = V2.list_suggested_edits(execution.id)
    allow_suggested_edits = execution.procedure_version.allow_suggested_edits

    socket
    |> assign(:page_title, "Executing: #{procedure.name}")
    |> assign(:procedure, procedure)
    |> assign(:execution, execution)
    |> assign(:steps_by_section, steps_by_section)
    |> assign(:step_executions, execution.step_executions)
    |> assign(:active_step_id, active_step_id)
    |> assign(:visible_step_id, active_step_id)
    |> assign(:step_comments, step_comments)
    |> assign(:suggested_edits, suggested_edits)
    |> assign(:allow_suggested_edits, allow_suggested_edits)
    |> assign(:execution_process, maybe_start_execution_process(socket, execution, execution_id))
    |> assign(:command_lifecycles, command_lifecycles)
  end

  defp maybe_start_execution_process(socket, execution, execution_id) do
    if connected?(socket) and execution.status in [:running, :paused] do
      user_id = socket.assigns.current_scope.user.id

      case ExecutionProcess.start_or_attach(execution_id, user_id: user_id) do
        {:ok, pid} -> pid
        {:error, _reason} -> nil
      end
    else
      nil
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Event Handlers
  # ────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("scroll_to_step", %{"id" => step_id}, socket) do
    # Push event to JS hook to scroll to this step
    {:noreply, push_event(socket, "scroll_to", %{target: "step-#{step_id}"})}
  end

  def handle_event("scroll_to_section", %{"id" => section_id}, socket) do
    # Push event to JS hook to scroll to this section
    {:noreply, push_event(socket, "scroll_to", %{target: "section-#{section_id}"})}
  end

  def handle_event("toggle_step_expanded", %{"id" => step_id}, socket) do
    expanded_ids = socket.assigns.expanded_step_ids

    new_expanded_ids =
      if MapSet.member?(expanded_ids, step_id) do
        MapSet.delete(expanded_ids, step_id)
      else
        MapSet.put(expanded_ids, step_id)
      end

    {:noreply, assign(socket, :expanded_step_ids, new_expanded_ids)}
  end

  def handle_event("toggle_section_collapsed", %{"id" => section_id}, socket) do
    collapsed_ids = socket.assigns.collapsed_section_ids

    new_collapsed_ids =
      if MapSet.member?(collapsed_ids, section_id) do
        MapSet.delete(collapsed_ids, section_id)
      else
        MapSet.put(collapsed_ids, section_id)
      end

    {:noreply, assign(socket, :collapsed_section_ids, new_collapsed_ids)}
  end

  def handle_event("step_visible", %{"id" => step_id}, socket) do
    {:noreply, assign(socket, :visible_step_id, step_id)}
  end

  def handle_event("toggle_activity", %{"step_id" => step_id}, socket) do
    hidden_ids = socket.assigns.hidden_activity_step_ids

    new_hidden_ids =
      if MapSet.member?(hidden_ids, step_id) do
        MapSet.delete(hidden_ids, step_id)
      else
        MapSet.put(hidden_ids, step_id)
      end

    {:noreply, assign(socket, :hidden_activity_step_ids, new_hidden_ids)}
  end

  def handle_event(
        "submit_input",
        %{"block_id" => block_id, "step_id" => step_id, "value" => value},
        socket
      )
      when is_binary(value) and value != "" do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.submit_block_input(execution_id, step_id, block_id, value, user_id: user_id) do
      :ok ->
        # State will be updated via PubSub
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit input: #{inspect(reason)}")}
    end
  end

  # Handle empty values (blur on empty field) - just ignore
  def handle_event("submit_input", _params, socket) do
    {:noreply, socket}
  end

  # Handle select input changes (phx-change sends value differently)
  def handle_event(
        "submit_select",
        %{"block_id" => block_id, "step_id" => step_id, "value" => value},
        socket
      )
      when is_binary(value) and value != "" do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.submit_block_input(execution_id, step_id, block_id, value, user_id: user_id) do
      :ok ->
        # State will be updated via PubSub
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit selection: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_select", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "submit_checkbox",
        %{"block_id" => block_id, "step_id" => step_id, "value" => value},
        socket
      ) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id
    checked = value in ["true", "on", true]

    case V2.submit_block_input(execution_id, step_id, block_id, checked, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit checkbox: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_checkbox", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_comment_form", %{"step_id" => step_id}, socket) do
    current = socket.assigns.commenting_step_id

    new_commenting_id =
      if current == step_id do
        nil
      else
        step_id
      end

    {:noreply,
     socket
     |> assign(:commenting_step_id, new_commenting_id)
     |> assign(:show_comment_form, not is_nil(new_commenting_id))}
  end

  def handle_event(
        "add_comment",
        %{"comment" => %{"content" => content, "step_id" => step_id}},
        socket
      )
      when content != "" do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.create_comment(%{
           procedure_execution_id: execution_id,
           step_execution_id: step_id,
           user_id: user_id,
           content: content
         }) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> assign(:step_comments, V2.list_comments(execution_id))
         |> assign(:commenting_step_id, nil)
         |> assign(:show_comment_form, false)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add comment: #{inspect(reason)}")}
    end
  end

  def handle_event("add_comment", _params, socket) do
    {:noreply, assign(socket, :commenting_step_id, nil) |> assign(:show_comment_form, false)}
  end

  def handle_event("toggle_suggested_edit_form", %{"step_id" => step_id}, socket) do
    current = socket.assigns.suggesting_step_id
    new_value = if current == step_id, do: nil, else: step_id
    {:noreply, assign(socket, :suggesting_step_id, new_value)}
  end

  def handle_event(
        "add_suggested_edit",
        %{"suggested_edit" => %{"reason" => reason, "step_id" => step_id}},
        socket
      )
      when reason != "" do
    execution = socket.assigns.execution
    user_id = socket.assigns.current_scope.user.id
    step_exec = Enum.find(socket.assigns.step_executions, &(&1.id == step_id))

    if socket.assigns.allow_suggested_edits and step_exec do
      attrs = %{
        procedure_execution_id: execution.id,
        step_execution_id: step_id,
        target_step_id: step_exec.step_id,
        suggested_by_id: user_id,
        edit_type: :modify_step,
        reason: reason,
        before_snapshot: step_snapshot(step_exec),
        after_snapshot: %{"note" => reason}
      }

      case V2.create_suggested_edit(attrs) do
        {:ok, _edit} ->
          {:noreply,
           socket
           |> assign(:suggested_edits, V2.list_suggested_edits(execution.id))
           |> assign(:suggesting_step_id, nil)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to add suggestion: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Suggested edits are disabled")}
    end
  end

  def handle_event("add_suggested_edit", _params, socket) do
    {:noreply, assign(socket, :suggesting_step_id, nil)}
  end

  def handle_event("accept_suggested_edit", %{"edit_id" => edit_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case V2.get_suggested_edit(edit_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Suggested edit not found")}

      edit ->
        case V2.accept_suggested_edit(edit, user_id) do
          {:ok, _} ->
            {:noreply,
             assign(
               socket,
               :suggested_edits,
               V2.list_suggested_edits(edit.procedure_execution_id)
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to accept: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("reject_suggested_edit", %{"edit_id" => edit_id, "note" => note}, socket) do
    user_id = socket.assigns.current_scope.user.id
    note = if note in [nil, ""], do: "Rejected", else: note

    case V2.get_suggested_edit(edit_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Suggested edit not found")}

      edit ->
        case V2.reject_suggested_edit(edit, user_id, note) do
          {:ok, _} ->
            {:noreply,
             assign(
               socket,
               :suggested_edits,
               V2.list_suggested_edits(edit.procedure_execution_id)
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to reject: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("sign_off", %{"step_id" => step_id, "role" => role} = params, socket) do
    note = params["note"]
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.sign_off_step_v2(execution_id, step_id, role, note, user_id: user_id) do
      :ok ->
        # State will be updated via PubSub
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to sign off: #{inspect(reason)}")}
    end
  end

  def handle_event("mark_step_complete", %{"step_id" => step_id}, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.complete_step_v2(execution_id, step_id, user_id: user_id) do
      :ok ->
        # State will be updated via PubSub
        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Cannot complete step: #{format_completion_error(reason)}")}
    end
  end

  def handle_event("skip_step", %{"skip" => %{"step_id" => step_id, "reason" => reason}}, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.skip_step_v2(execution_id, step_id, reason, user_id: user_id) do
      :ok ->
        # State will be updated via PubSub
        {:noreply, socket}

      {:error, error_reason} ->
        {:noreply, put_flash(socket, :error, "Failed to skip step: #{inspect(error_reason)}")}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Execution Control Events
  # ────────────────────────────────────────────────────────────────────

  def handle_event("pause_execution", _params, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.pause_execution_v2(execution_id, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
    end
  end

  def handle_event("resume_execution", _params, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.resume_execution_v2(execution_id, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
    end
  end

  def handle_event("abort_execution", %{"abort" => %{"reason" => reason}}, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.abort_execution(execution_id, reason, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to abort: #{inspect(error)}")}
    end
  end

  def handle_event("retry_block", %{"step_id" => step_id, "block_id" => block_id}, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.retry_block(execution_id, step_id, block_id, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to retry block: #{inspect(reason)}")}
    end
  end

  def handle_event("retry_step", %{"step_id" => step_id}, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.retry_step(execution_id, step_id, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to retry step: #{inspect(reason)}")}
    end
  end

  def handle_event("send_command", %{"step_id" => step_id, "block_id" => block_id}, socket) do
    execution_id = socket.assigns.execution.id
    user_id = socket.assigns.current_scope.user.id

    case V2.execute_block(execution_id, step_id, block_id, user_id: user_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send command: #{inspect(reason)}")}
    end
  end

  defp format_completion_error(:signoff_requirements_not_met), do: "Signoff requirements not met"

  defp format_completion_error({:step_not_completable, status}),
    do: "Step is #{status}, cannot complete"

  defp format_completion_error({:incomplete_required_inputs, names}),
    do: "Missing required inputs: #{Enum.join(names, ", ")}"

  defp format_completion_error({:failed_checks, names}),
    do: "Failed checks: #{Enum.join(names, ", ")}"

  defp format_completion_error(reason), do: inspect(reason)

  # ────────────────────────────────────────────────────────────────────
  # PubSub Handlers
  # ────────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:step_activated, step_exec}, socket) do
    {:noreply, reload_and_update(socket, :step_activated, step_exec)}
  end

  def handle_info({:step_completed, step_exec}, socket) do
    {:noreply, reload_and_update(socket, :step_completed, step_exec)}
  end

  def handle_info({:step_skipped, step_exec}, socket) do
    {:noreply, reload_and_update(socket, :step_skipped, step_exec)}
  end

  def handle_info({:step_failed, step_exec, _reason}, socket) do
    {:noreply, reload_and_update(socket, :step_failed, step_exec)}
  end

  def handle_info({:block_updated, _block_exec}, socket) do
    # Reload execution to get updated block state
    {:noreply, reload_and_update(socket, :block_updated, nil)}
  end

  def handle_info({:signoff_added, _signoff}, socket) do
    # Reload execution to get updated signoff state
    {:noreply, reload_and_update(socket, :signoff_added, nil)}
  end

  # Automation progress events
  def handle_info({:automation_progress, block, status, data}, socket) do
    socket =
      socket
      |> assign(:automation_running, status in [:starting, :running, :waiting])
      |> assign(:automation_block_id, block.id)
      |> assign(:automation_status, %{status: status, data: data})

    {:noreply, socket}
  end

  def handle_info({:step_awaiting_input, _step_exec}, socket) do
    {:noreply, assign(socket, :automation_running, false)}
  end

  def handle_info({:block_failed, _block, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:automation_running, false)
     |> reload_and_update(:block_failed, nil)}
  end

  # Execution lifecycle events
  def handle_info({:execution_paused, execution}, socket) do
    {:noreply, assign(socket, :execution, execution)}
  end

  def handle_info({:execution_resumed, execution}, socket) do
    {:noreply, assign(socket, :execution, execution)}
  end

  def handle_info({:execution_completed, execution}, socket) do
    {:noreply,
     socket
     |> assign(:execution, execution)
     |> assign(:automation_running, false)
     |> put_flash(:info, "Execution completed successfully")}
  end

  def handle_info({:execution_failed, execution, reason}, socket) do
    {:noreply,
     socket
     |> assign(:execution, execution)
     |> assign(:automation_running, false)
     |> put_flash(:error, "Execution failed: #{reason}")}
  end

  def handle_info({:status_changed, _status, _execution}, socket) do
    execution = V2.get_execution_with_steps(socket.assigns.execution.id)
    {:noreply, assign(socket, :execution, execution)}
  end

  # ────────────────────────────────────────────────────────────────────
  # Outbox Event Handlers (Command Lifecycle)
  # ────────────────────────────────────────────────────────────────────

  def handle_info(
        {:outbox_event, %{event_type: event_type, aggregate_id: queue_entry_id} = event},
        socket
      )
      when event_type in ["command_enqueued", "command_status_changed"] do
    # Only process if this queue_entry_id is tracked by our execution
    if tracked_queue_entry?(socket, queue_entry_id) do
      {:noreply, update_command_lifecycle(socket, queue_entry_id, event)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:outbox_event, _event}, socket) do
    # Ignore other outbox event types
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp reload_and_update(socket, _event_type, _step_exec) do
    execution = V2.get_execution_with_steps(socket.assigns.execution.id)
    steps_by_section = group_steps_by_section(execution.step_executions)
    active_step = find_active_step(execution.step_executions)
    prev_active_id = socket.assigns.active_step_id
    new_active_id = active_step && active_step.id
    step_comments = V2.list_comments(execution.id)
    suggested_edits = V2.list_suggested_edits(execution.id)
    allow_suggested_edits = execution.procedure_version.allow_suggested_edits

    socket =
      socket
      |> assign(:execution, execution)
      |> assign(:step_executions, execution.step_executions)
      |> assign(:steps_by_section, steps_by_section)
      |> assign(:active_step_id, new_active_id)
      |> assign(:step_comments, step_comments)
      |> assign(:suggested_edits, suggested_edits)
      |> assign(:allow_suggested_edits, allow_suggested_edits)

    # Auto-scroll to new active step if it changed
    if new_active_id && new_active_id != prev_active_id do
      push_event(socket, "scroll_to", %{target: "step-#{new_active_id}"})
    else
      socket
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Private Helpers
  # ────────────────────────────────────────────────────────────────────

  defp group_steps_by_section(step_executions) do
    step_executions
    |> Enum.group_by(fn se -> se.step.section end)
    |> Enum.sort_by(fn {section, _} -> section.position end)
  end

  defp find_active_step(step_executions) do
    Enum.find(step_executions, fn se ->
      se.status in [:active, :awaiting_signoff]
    end) || Enum.find(step_executions, &(&1.status == :pending))
  end

  # Generate section letter from index (0 -> A, 1 -> B, etc.)
  defp section_letter(index) when is_integer(index), do: <<65 + index>>

  # ────────────────────────────────────────────────────────────────────
  # Command Lifecycle Helpers
  # ────────────────────────────────────────────────────────────────────

  @doc false
  defp build_initial_command_lifecycles(execution) do
    # Extract all queue_entry_ids from command block results
    queue_entry_ids =
      execution.step_executions
      |> Enum.flat_map(& &1.block_executions)
      |> Enum.filter(&has_queue_entry_id?/1)
      |> Enum.map(&get_queue_entry_id/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(queue_entry_ids) do
      %{}
    else
      ExecutionQueries.get_command_lifecycles(queue_entry_ids)
    end
  end

  defp has_queue_entry_id?(%BlockExecution{command_result: %{"command_id" => _}}), do: true
  defp has_queue_entry_id?(_), do: false

  defp get_queue_entry_id(%BlockExecution{command_result: %{"command_id" => id}}), do: id
  defp get_queue_entry_id(_), do: nil

  defp tracked_queue_entry?(socket, queue_entry_id) do
    # Check if this queue_entry_id belongs to any of our block executions
    socket.assigns.step_executions
    |> Enum.flat_map(& &1.block_executions)
    |> Enum.any?(fn be ->
      get_queue_entry_id(be) == queue_entry_id
    end)
  end

  defp update_command_lifecycle(socket, queue_entry_id, event) do
    lifecycle_event = %{
      state: extract_command_state(event),
      timestamp: event.inserted_at,
      details: %{
        command_name: get_in(event.payload, ["command_name"]),
        command_log_id: get_in(event.payload, ["command_log_id"]),
        target_id: get_in(event.payload, ["target_id"]),
        error: get_in(event.payload, ["last_error"])
      }
    }

    update(socket, :command_lifecycles, fn lifecycles ->
      Map.update(lifecycles, queue_entry_id, [lifecycle_event], fn events ->
        events ++ [lifecycle_event]
      end)
    end)
  end

  defp extract_command_state(%{event_type: "command_enqueued"}), do: :queued

  defp extract_command_state(%{event_type: "command_status_changed", payload: payload}) do
    case payload["status"] do
      "pending" -> :queued
      "executing" -> :executing
      "completed" -> :sent
      "failed" -> :failed
      "cancelled" -> :cancelled
      "expired" -> :expired
      _ -> :unknown
    end
  end

  # Get lifecycle for a specific command block from the lifecycles map
  defp get_command_lifecycle(nil, _lifecycles), do: []

  defp get_command_lifecycle(block_execution, lifecycles) do
    case block_execution.command_result do
      %{"command_id" => queue_entry_id} -> Map.get(lifecycles, queue_entry_id, [])
      _ -> []
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Render
  # ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    # Calculate progress
    total_steps = length(assigns.step_executions)
    completed_steps = Enum.count(assigns.step_executions, &(&1.status == :completed))
    progress_percent = if total_steps > 0, do: round(completed_steps / total_steps * 100), else: 0

    assigns =
      assigns
      |> assign(:total_steps, total_steps)
      |> assign(:completed_steps, completed_steps)
      |> assign(:progress_percent, progress_percent)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="h-[calc(100vh-4rem)] flex flex-col" id="procedure-execution">
        <!-- Header with Progress -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-300 bg-base-200">
          <div class="flex items-center gap-3">
            <.link
              navigate={~p"/missions/#{@mission}/procedures/#{@procedure}"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" />
            </.link>
            <div>
              <h1 class="text-lg font-bold">{@procedure.name}</h1>
              <span class="text-sm text-base-content/60">Execution</span>
            </div>
          </div>
          
    <!-- Progress Section -->
          <div class="flex items-center gap-4">
            <.execution_mode_badge mode={@execution.procedure_version.execution_mode || :manual} />
            <.execution_status_badge status={@execution.status} />
            
    <!-- Automation Running Indicator -->
            <%= if @automation_running do %>
              <div class="flex items-center gap-2 text-primary">
                <span class="loading loading-spinner loading-xs"></span>
                <span class="text-sm">Automation Running</span>
              </div>
            <% end %>
            
    <!-- Progress Bar -->
            <div class="flex items-center gap-3">
              <div class="w-32 h-2 bg-base-300 rounded-full overflow-hidden">
                <div
                  class="h-full bg-success transition-all duration-500 ease-out"
                  style={"width: #{@progress_percent}%"}
                >
                </div>
              </div>
              <span class="text-sm font-mono text-base-content/70">
                {@completed_steps}/{@total_steps}
              </span>
            </div>
            
    <!-- Execution Controls -->
            <.execution_controls
              status={@execution.status}
              execution_process={@execution_process}
            />
          </div>
        </div>
        
    <!-- Three Column Layout -->
        <div class="flex-1 flex overflow-hidden">
          <!-- Left Panel: Navigation Index -->
          <div class="w-64 border-r border-base-300 bg-base-100 flex flex-col">
            <div class="p-3 border-b border-base-300">
              <span class="font-semibold text-sm uppercase tracking-wide text-base-content/70">
                Navigation
              </span>
            </div>
            <div class="flex-1 overflow-y-auto p-2">
              <%= for {{section, step_execs}, section_idx} <- Enum.with_index(@steps_by_section) do %>
                <.nav_section
                  section={section}
                  section_letter={section_letter(section_idx)}
                  step_executions={step_execs}
                  visible_step_id={@visible_step_id}
                  active_step_id={@active_step_id}
                  collapsed={MapSet.member?(@collapsed_section_ids, section.id)}
                />
              <% end %>
            </div>
            <div class="p-3 border-t border-base-300 text-xs text-base-content/60">
              <div class="flex items-center gap-2">
                <span class="text-success">●</span> Completed
              </div>
              <div class="flex items-center gap-2">
                <span class="text-primary">●</span> Active
              </div>
              <div class="flex items-center gap-2">
                <span class="text-base-content/30">○</span> Pending
              </div>
            </div>
          </div>
          
    <!-- Center Panel: Full Procedure Document -->
          <div class="flex-1 bg-base-200/50 flex flex-col overflow-hidden">
            <div
              class="flex-1 overflow-y-auto"
              id="procedure-scroll-container"
              phx-hook="ProcedureNav"
            >
              <.procedure_document
                steps_by_section={@steps_by_section}
                step_comments={@step_comments}
                suggested_edits={@suggested_edits}
                allow_suggested_edits={@allow_suggested_edits}
                user={@current_scope.user}
                expanded_step_ids={@expanded_step_ids}
                collapsed_section_ids={@collapsed_section_ids}
                hidden_activity_step_ids={@hidden_activity_step_ids}
                commenting_step_id={@commenting_step_id}
                suggesting_step_id={@suggesting_step_id}
                active_step_id={@active_step_id}
                command_lifecycles={@command_lifecycles}
                comment_form={@comment_form}
                suggested_edit_form={@suggested_edit_form}
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Components
  # ────────────────────────────────────────────────────────────────────

  attr :mode, :atom, required: true

  defp execution_mode_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-outline text-xs",
      @mode == :manual && "badge-info",
      @mode == :assisted && "badge-warning",
      @mode == :automatic && "badge-success"
    ]}>
      <.icon name={mode_icon(@mode)} class="h-3 w-3 mr-1" />
      {format_mode(@mode)}
    </span>
    """
  end

  defp mode_icon(:manual), do: "hero-hand-raised"
  defp mode_icon(:assisted), do: "hero-sparkles"
  defp mode_icon(:automatic), do: "hero-bolt"
  defp mode_icon(_), do: "hero-hand-raised"

  defp format_mode(:manual), do: "Manual"
  defp format_mode(:assisted), do: "Assisted"
  defp format_mode(:automatic), do: "Automatic"
  defp format_mode(_), do: "Manual"

  attr :status, :atom, required: true

  defp execution_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge",
      @status == :running && "badge-primary",
      @status == :completed && "badge-success",
      @status == :failed && "badge-error",
      @status == :paused && "badge-warning",
      @status == :cancelled && "badge-ghost"
    ]}>
      {@status}
    </span>
    """
  end

  # ── Execution Controls (Pause/Resume/Abort) ────────────────────────────────────────

  attr :status, :atom, required: true
  attr :execution_process, :any, default: nil

  defp execution_controls(assigns) do
    assigns = assign(assigns, :abort_form, to_form(%{}, as: :abort))

    ~H"""
    <div class="flex items-center gap-2">
      <%= case @status do %>
        <% :running -> %>
          <button
            type="button"
            phx-click="pause_execution"
            class="btn btn-sm btn-ghost gap-1"
            title="Pause execution"
          >
            <.icon name="hero-pause" class="h-4 w-4" />
            <span class="hidden sm:inline">Pause</span>
          </button>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-sm btn-ghost btn-error gap-1">
              <.icon name="hero-x-mark" class="h-4 w-4" />
              <span class="hidden sm:inline">Abort</span>
            </label>
            <div tabindex="0" class="dropdown-content z-[1] p-4 shadow-lg bg-base-100 rounded-lg w-72">
              <.form for={@abort_form} id="abort-execution-form-running" phx-submit="abort_execution">
                <p class="text-sm mb-2">Are you sure you want to abort this execution?</p>
                <.input
                  type="text"
                  field={@abort_form[:reason]}
                  id="abort-execution-reason-running"
                  placeholder="Reason for aborting..."
                  class="input input-bordered input-sm w-full mb-2"
                  required
                />
                <div class="flex justify-end gap-2">
                  <button type="submit" class="btn btn-error btn-sm">Abort</button>
                </div>
              </.form>
            </div>
          </div>
        <% :paused -> %>
          <button
            type="button"
            phx-click="resume_execution"
            class="btn btn-sm btn-primary gap-1"
            title="Resume execution"
          >
            <.icon name="hero-play" class="h-4 w-4" />
            <span class="hidden sm:inline">Resume</span>
          </button>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-sm btn-ghost btn-error gap-1">
              <.icon name="hero-x-mark" class="h-4 w-4" />
              <span class="hidden sm:inline">Abort</span>
            </label>
            <div tabindex="0" class="dropdown-content z-[1] p-4 shadow-lg bg-base-100 rounded-lg w-72">
              <.form for={@abort_form} id="abort-execution-form-paused" phx-submit="abort_execution">
                <p class="text-sm mb-2">Are you sure you want to abort this execution?</p>
                <.input
                  type="text"
                  field={@abort_form[:reason]}
                  id="abort-execution-reason-paused"
                  placeholder="Reason for aborting..."
                  class="input input-bordered input-sm w-full mb-2"
                  required
                />
                <div class="flex justify-end gap-2">
                  <button type="submit" class="btn btn-error btn-sm">Abort</button>
                </div>
              </.form>
            </div>
          </div>
        <% _other -> %>
          <%!-- No controls for completed/failed/cancelled --%>
      <% end %>
    </div>
    """
  end

  # ── Step Number Badge (Epsilon3-style: black circle with white text) ─────────────────

  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true
  attr :status, :atom, required: true

  defp step_number_badge(assigns) do
    ~H"""
    <span class={[
      "w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold shrink-0",
      @status == :completed && "bg-neutral text-neutral-content",
      @status in [:active, :awaiting_signoff] && "bg-neutral text-neutral-content",
      @status == :failed && "bg-error text-error-content",
      @status == :skipped && "bg-base-300 text-base-content/50",
      @status in [:pending, :blocked] && "bg-neutral/50 text-neutral-content/70"
    ]}>
      {@section_letter}{@step_index}
    </span>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Navigation Sidebar Components
  # ────────────────────────────────────────────────────────────────────

  # Timeline dot for nav (Epsilon3-style: filled/hollow circles)
  attr :status, :atom, required: true

  defp timeline_dot(assigns) do
    ~H"""
    <span class={[
      "w-3 h-3 rounded-full shrink-0 border-2",
      @status == :completed && "bg-success border-success",
      @status in [:active, :awaiting_signoff] && "bg-success border-success",
      @status == :failed && "bg-error border-error",
      @status == :skipped && "bg-base-300 border-base-300",
      @status in [:pending, :blocked] && "bg-transparent border-base-content/30"
    ]} />
    """
  end

  attr :section, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_executions, :list, required: true
  attr :visible_step_id, :string, default: nil
  attr :active_step_id, :string, default: nil
  attr :collapsed, :boolean, default: false

  defp nav_section(assigns) do
    step_count = length(assigns.step_executions)
    assigns = assign(assigns, :step_count, step_count)

    ~H"""
    <div class="mb-2">
      <!-- Section Header (Clean, no progress counter) -->
      <div
        class="flex items-center gap-2 px-2 py-1.5 cursor-pointer hover:bg-base-200/50 rounded transition-colors"
        phx-click="scroll_to_section"
        phx-value-id={@section.id}
      >
        <button
          type="button"
          phx-click="toggle_section_collapsed"
          phx-value-id={@section.id}
          class="text-base-content/50 hover:text-base-content"
        >
          <%= if @collapsed do %>
            <.icon name="hero-chevron-right" class="h-3 w-3" />
          <% else %>
            <.icon name="hero-chevron-down" class="h-3 w-3" />
          <% end %>
        </button>
        <span class="text-sm font-medium text-base-content/80 truncate">
          {@section_letter}: {@section.name}
        </span>
      </div>
      
    <!-- Steps Timeline (Epsilon3-style) -->
      <%= unless @collapsed do %>
        <div class="ml-5 mt-1">
          <%= for {step_exec, step_idx} <- Enum.with_index(@step_executions) do %>
            <div
              class={[
                "relative flex gap-3 px-2 cursor-pointer rounded transition-all duration-150",
                step_exec.id == @visible_step_id && "bg-primary/10",
                step_exec.status not in [:pending, :blocked] && "hover:bg-base-200/50",
                step_exec.status in [:pending, :blocked] && "hover:bg-base-200/30"
              ]}
              phx-click="scroll_to_step"
              phx-value-id={step_exec.id}
            >
              <!-- Timeline column: line segments + dot -->
              <div class="relative w-3 h-8 shrink-0">
                <!-- Line ABOVE dot (always show for continuity between sections) -->
                <div class="absolute top-0 left-1/2 -translate-x-1/2 h-1/2 w-px bg-base-content/20">
                </div>
                <!-- Dot (centered, on top of lines) -->
                <span class={[
                  "absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-10",
                  "w-3 h-3 rounded-full border-2 block",
                  step_exec.status == :completed && "bg-success border-success",
                  step_exec.status in [:active, :awaiting_signoff] && "bg-primary border-primary",
                  step_exec.status == :failed && "bg-error border-error",
                  step_exec.status == :skipped && "bg-base-300 border-base-300",
                  step_exec.status in [:pending, :blocked] && "bg-transparent border-base-content/30"
                ]} />
                <!-- Line BELOW dot (always show for continuity between sections) -->
                <div class="absolute bottom-0 left-1/2 -translate-x-1/2 h-1/2 w-px bg-base-content/20">
                </div>
              </div>
              
    <!-- Step label: "A1  Step Name" -->
              <div class="flex-1 flex items-center gap-2 min-h-[32px]">
                <span class={[
                  "text-sm truncate flex-1",
                  step_exec.status == :completed && "text-base-content",
                  step_exec.status in [:active, :awaiting_signoff] && "text-base-content font-medium",
                  step_exec.status == :failed && "text-error",
                  step_exec.status == :skipped && "text-base-content/50 line-through",
                  step_exec.status in [:pending, :blocked] && "text-base-content/60"
                ]}>
                  <span class="font-medium">{@section_letter}{step_idx + 1}</span>
                  <span class="mx-1.5">{step_exec.step.name}</span>
                </span>
                
    <!-- Active step pulsing indicator -->
                <%= if step_exec.id == @active_step_id do %>
                  <span class="relative flex h-2 w-2 shrink-0">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75">
                    </span>
                    <span class="relative inline-flex rounded-full h-2 w-2 bg-primary"></span>
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Procedure Document Components (Full scrollable view)
  # ────────────────────────────────────────────────────────────────────

  attr :steps_by_section, :list, required: true
  attr :step_comments, :list, required: true
  attr :suggested_edits, :list, required: true
  attr :allow_suggested_edits, :boolean, required: true
  attr :user, :map, required: true
  attr :expanded_step_ids, :any, required: true
  attr :collapsed_section_ids, :any, required: true
  attr :hidden_activity_step_ids, :any, required: true
  attr :commenting_step_id, :string, default: nil
  attr :suggesting_step_id, :string, default: nil
  attr :active_step_id, :string, default: nil
  attr :command_lifecycles, :map, default: %{}
  attr :comment_form, :map, required: true
  attr :suggested_edit_form, :map, required: true

  defp procedure_document(assigns) do
    ~H"""
    <div class="p-4 space-y-6">
      <%= for {{section, step_execs}, section_idx} <- Enum.with_index(@steps_by_section) do %>
        <.document_section
          section={section}
          section_letter={section_letter(section_idx)}
          step_executions={step_execs}
          step_comments={@step_comments}
          suggested_edits={@suggested_edits}
          allow_suggested_edits={@allow_suggested_edits}
          user={@user}
          expanded_step_ids={@expanded_step_ids}
          hidden_activity_step_ids={@hidden_activity_step_ids}
          collapsed={MapSet.member?(@collapsed_section_ids, section.id)}
          commenting_step_id={@commenting_step_id}
          suggesting_step_id={@suggesting_step_id}
          active_step_id={@active_step_id}
          command_lifecycles={@command_lifecycles}
          comment_form={@comment_form}
          suggested_edit_form={@suggested_edit_form}
        />
      <% end %>
    </div>
    """
  end

  attr :section, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_executions, :list, required: true
  attr :step_comments, :list, required: true
  attr :suggested_edits, :list, required: true
  attr :allow_suggested_edits, :boolean, required: true
  attr :user, :map, required: true
  attr :expanded_step_ids, :any, required: true
  attr :hidden_activity_step_ids, :any, required: true
  attr :collapsed, :boolean, default: false
  attr :commenting_step_id, :string, default: nil
  attr :suggesting_step_id, :string, default: nil
  attr :active_step_id, :string, default: nil
  attr :command_lifecycles, :map, default: %{}
  attr :comment_form, :map, required: true
  attr :suggested_edit_form, :map, required: true

  defp document_section(assigns) do
    completed = Enum.count(assigns.step_executions, &(&1.status == :completed))
    total = length(assigns.step_executions)
    progress = if total > 0, do: round(completed / total * 100), else: 0

    assigns =
      assigns
      |> assign(:completed, completed)
      |> assign(:total, total)
      |> assign(:progress, progress)

    ~H"""
    <div id={"section-#{@section.id}"} class="scroll-mt-4">
      <!-- Sticky Section Header (Epsilon3 style) -->
      <div class="sticky top-0 z-10 bg-base-200 border border-base-300 rounded-lg shadow-sm mb-4">
        <div class="flex items-center justify-between p-3">
          <div class="flex items-center gap-3">
            <button
              type="button"
              phx-click="toggle_section_collapsed"
              phx-value-id={@section.id}
              class="btn btn-ghost btn-xs"
            >
              <%= if @collapsed do %>
                <.icon name="hero-chevron-right" class="h-4 w-4" />
              <% else %>
                <.icon name="hero-chevron-down" class="h-4 w-4" />
              <% end %>
            </button>
            <span class="font-semibold text-base-content">
              Section {@section_letter}: {@section.name}
            </span>
          </div>

          <div class="flex items-center gap-3">
            <!-- Inline progress bar with percentage -->
            <div class="flex items-center gap-2">
              <div class="w-24 h-2 bg-base-300 rounded-full overflow-hidden">
                <div
                  class={[
                    "h-full transition-all duration-300",
                    @progress == 100 && "bg-success",
                    @progress > 0 && @progress < 100 && "bg-primary",
                    @progress == 0 && "bg-base-300"
                  ]}
                  style={"width: #{@progress}%"}
                >
                </div>
              </div>
              <span class="text-sm font-medium text-base-content/70">
                {@progress}%
              </span>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Section Steps -->
      <%= unless @collapsed do %>
        <div class="space-y-4 pl-2">
          <%= for {step_exec, step_idx} <- Enum.with_index(@step_executions) do %>
            <.step_card
              step_execution={step_exec}
              section_letter={@section_letter}
              step_index={step_idx + 1}
              step_comments={Enum.filter(@step_comments, &(&1.step_execution_id == step_exec.id))}
              step_suggested_edits={
                Enum.filter(@suggested_edits, &(&1.step_execution_id == step_exec.id))
              }
              allow_suggested_edits={@allow_suggested_edits}
              user={@user}
              is_expanded={MapSet.member?(@expanded_step_ids, step_exec.id)}
              is_activity_hidden={MapSet.member?(@hidden_activity_step_ids, step_exec.id)}
              is_active={step_exec.id == @active_step_id}
              command_lifecycles={@command_lifecycles}
              commenting_step_id={@commenting_step_id}
              suggesting_step_id={@suggesting_step_id}
              comment_form={@comment_form}
              suggested_edit_form={@suggested_edit_form}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :step_execution, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true
  attr :step_comments, :list, required: true
  attr :step_suggested_edits, :list, required: true
  attr :allow_suggested_edits, :boolean, required: true
  attr :user, :map, required: true
  attr :is_expanded, :boolean, default: false
  attr :is_activity_hidden, :boolean, default: false
  attr :is_active, :boolean, default: false
  attr :command_lifecycles, :map, default: %{}
  attr :commenting_step_id, :string, default: nil
  attr :suggesting_step_id, :string, default: nil
  attr :comment_form, :map, required: true
  attr :suggested_edit_form, :map, required: true

  defp step_card(assigns) do
    step = assigns.step_execution.step
    status = assigns.step_execution.status

    # Determine which card variant to render
    card_type =
      cond do
        status in [:active, :awaiting_signoff] -> :active
        status == :completed -> :completed
        status == :failed -> :failed
        status in [:pending, :blocked] -> :pending
        status == :skipped -> :skipped
        true -> :pending
      end

    assigns =
      assigns
      |> assign(:step, step)
      |> assign(:status, status)
      |> assign(:card_type, card_type)

    ~H"""
    <div
      id={"step-#{@step_execution.id}"}
      data-step-id={@step_execution.id}
      data-step-status={@status}
      class="scroll-mt-20"
    >
      <%= case @card_type do %>
        <% :active -> %>
          <.step_card_active
            step_execution={@step_execution}
            step={@step}
            section_letter={@section_letter}
            step_index={@step_index}
            step_comments={@step_comments}
            step_suggested_edits={@step_suggested_edits}
            allow_suggested_edits={@allow_suggested_edits}
            user={@user}
            is_activity_hidden={@is_activity_hidden}
            command_lifecycles={@command_lifecycles}
            commenting_step_id={@commenting_step_id}
            suggesting_step_id={@suggesting_step_id}
            comment_form={@comment_form}
            suggested_edit_form={@suggested_edit_form}
          />
        <% :completed -> %>
          <.step_card_completed
            step_execution={@step_execution}
            step={@step}
            section_letter={@section_letter}
            step_index={@step_index}
            step_comments={@step_comments}
            is_expanded={@is_expanded}
            command_lifecycles={@command_lifecycles}
          />
        <% :failed -> %>
          <.step_card_failed
            step_execution={@step_execution}
            step={@step}
            section_letter={@section_letter}
            step_index={@step_index}
            step_comments={@step_comments}
            command_lifecycles={@command_lifecycles}
          />
        <% :pending -> %>
          <.step_card_pending
            step_execution={@step_execution}
            step={@step}
            section_letter={@section_letter}
            step_index={@step_index}
          />
        <% :skipped -> %>
          <.step_card_skipped
            step_execution={@step_execution}
            step={@step}
            section_letter={@section_letter}
            step_index={@step_index}
          />
      <% end %>
    </div>
    """
  end

  # ── Active Step Card ──────────────────────────────────────────────────

  attr :step_execution, :map, required: true
  attr :step, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true
  attr :step_comments, :list, required: true
  attr :step_suggested_edits, :list, required: true
  attr :allow_suggested_edits, :boolean, required: true
  attr :user, :map, required: true
  attr :is_activity_hidden, :boolean, default: false
  attr :command_lifecycles, :map, default: %{}
  attr :commenting_step_id, :string, default: nil
  attr :suggesting_step_id, :string, default: nil
  attr :comment_form, :map, required: true
  attr :suggested_edit_form, :map, required: true

  defp step_card_active(assigns) do
    blocks = assigns.step.blocks || []
    block_executions = assigns.step_execution.block_executions || []
    signoffs = assigns.step_execution.signoffs || []

    assigns =
      assigns
      |> assign(:blocks, blocks)
      |> assign(:block_executions, block_executions)
      |> assign(:signoffs, signoffs)

    ~H"""
    <div class="bg-base-100 rounded-lg border border-primary/50 shadow-sm">
      <!-- Step Header -->
      <div class="p-3 flex items-center gap-3">
        <button type="button" class="text-base-content/50 hover:text-base-content">
          <.icon name="hero-chevron-down" class="h-4 w-4" />
        </button>
        <.step_number_badge
          section_letter={@section_letter}
          step_index={@step_index}
          status={@step_execution.status}
        />
        <h3 class="font-semibold flex-1">{@step.title || @step.name}</h3>
        <div class="flex items-center gap-2">
          <!-- Status: awaiting signoff or in progress -->
          <span class="w-8 h-8 rounded-full border-2 border-base-300 flex items-center justify-center">
            <.icon name="hero-clock" class="h-4 w-4 text-base-content/50" />
          </span>
          <button type="button" class="btn btn-ghost btn-sm btn-square">
            <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
          </button>
        </div>
      </div>
      
    <!-- Blocks -->
      <div class="px-4 pb-4 pl-16 space-y-3">
        <%= for block <- @blocks do %>
          <.block_execution_card
            block={block}
            block_execution={find_block_execution(@block_executions, block.id)}
            step_execution={@step_execution}
            step_status={@step_execution.status}
            command_lifecycles={@command_lifecycles}
          />
        <% end %>
      </div>
      
    <!-- Signoff Section -->
      <%= if @step.requires_signoff do %>
        <div class="px-4 pb-4 pl-16">
          <.signoff_panel
            step={@step}
            step_execution={@step_execution}
            signoffs={@signoffs}
            user={@user}
          />
        </div>
      <% end %>
      
    <!-- Activity Section -->
      <div class="border-t border-base-200 pl-16">
        <button
          type="button"
          phx-click="toggle_activity"
          phx-value-step_id={@step_execution.id}
          class="w-full px-4 py-2 flex items-center gap-2 text-sm text-base-content/60 hover:text-base-content transition-colors"
        >
          <%= if @is_activity_hidden do %>
            <.icon name="hero-plus" class="h-3 w-3" />
            <span>Show Activity</span>
          <% else %>
            <.icon name="hero-minus" class="h-3 w-3" />
            <span>Hide Activity</span>
          <% end %>
        </button>

        <%= unless @is_activity_hidden do %>
          <div class="px-4 pb-3 space-y-2">
            <%= for signoff <- @signoffs do %>
              <div class="flex items-center gap-2 text-sm">
                <.icon name="hero-check-circle-solid" class="h-4 w-4 text-primary" />
                <span>Signoff by</span>
                <span class="font-medium">{signoff.user.email}</span>
                <span class="text-base-content/50">
                  {format_time_with_seconds(signoff.inserted_at)}
                </span>
              </div>
            <% end %>

            <%= for comment <- @step_comments do %>
              <div class="flex items-center gap-2 text-sm">
                <.icon name="hero-chat-bubble-left" class="h-4 w-4 text-base-content/50" />
                <span>{comment.content}</span>
                <span class="text-base-content/50">- {short_email(comment.user.email)}</span>
              </div>
            <% end %>

            <%= for edit <- @step_suggested_edits do %>
              <div class="flex flex-wrap items-center gap-2 text-sm">
                <.icon name="hero-pencil-square" class="h-4 w-4 text-warning" />
                <span class="font-medium">Suggested edit</span>
                <span class="text-base-content/60">{edit.reason}</span>
                <span class={[
                  "badge badge-xs",
                  edit.status == :pending && "badge-warning",
                  edit.status == :accepted && "badge-success",
                  edit.status == :rejected && "badge-ghost"
                ]}>
                  {edit.status}
                </span>
                <%= if edit.status == :pending do %>
                  <button
                    type="button"
                    class="btn btn-xs btn-success"
                    phx-click="accept_suggested_edit"
                    phx-value-edit_id={edit.id}
                  >
                    Accept
                  </button>
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost"
                    phx-click="reject_suggested_edit"
                    phx-value-edit_id={edit.id}
                    phx-value-note="Rejected"
                  >
                    Reject
                  </button>
                <% end %>
              </div>
            <% end %>
            
    <!-- Comment Input -->
            <.form
              for={@comment_form}
              id={"step-comment-form-#{@step_execution.id}"}
              phx-submit="add_comment"
              class="flex items-center gap-2 mt-2"
            >
              <input type="hidden" name="comment[step_id]" value={@step_execution.id} />
              <.input
                type="text"
                field={@comment_form[:content]}
                id={"comment-content-#{@step_execution.id}"}
                placeholder="Add comment"
                class="input input-bordered input-sm flex-1 bg-base-200/50"
              />
              <button type="submit" class="btn btn-ghost btn-sm">Post ›</button>
            </.form>

            <div class="mt-2">
              <%= if @allow_suggested_edits do %>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="toggle_suggested_edit_form"
                  phx-value-step_id={@step_execution.id}
                >
                  <.icon name="hero-pencil-square" class="h-3 w-3" /> Suggest edit
                </button>
                <%= if @suggesting_step_id == @step_execution.id do %>
                  <.form
                    for={@suggested_edit_form}
                    id={"suggested-edit-form-#{@step_execution.id}"}
                    phx-submit="add_suggested_edit"
                    class="flex items-center gap-2 mt-2"
                  >
                    <input type="hidden" name="suggested_edit[step_id]" value={@step_execution.id} />
                    <.input
                      type="text"
                      field={@suggested_edit_form[:reason]}
                      id={"suggested-edit-reason-#{@step_execution.id}"}
                      placeholder="Describe the change"
                      class="input input-bordered input-sm flex-1 bg-base-200/50"
                    />
                    <button type="submit" class="btn btn-warning btn-sm">Send</button>
                  </.form>
                <% end %>
              <% else %>
                <span class="text-xs text-base-content/50">Suggested edits disabled</span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Completed Step Card ───────────────────────────────────────────────

  attr :step_execution, :map, required: true
  attr :step, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true
  attr :step_comments, :list, required: true
  attr :is_expanded, :boolean, default: false
  attr :command_lifecycles, :map, default: %{}

  defp step_card_completed(assigns) do
    signoffs = assigns.step_execution.signoffs || []
    first_signoff = List.first(signoffs)

    assigns = assign(assigns, :first_signoff, first_signoff)

    ~H"""
    <div class="bg-base-100 rounded-lg border border-success/30 border-l-4 border-l-success">
      <!-- Header -->
      <div
        class="p-3 flex items-center gap-3 cursor-pointer hover:bg-base-200/30"
        phx-click="toggle_step_expanded"
        phx-value-id={@step_execution.id}
      >
        <button type="button" class="text-base-content/50 hover:text-base-content">
          <%= if @is_expanded do %>
            <.icon name="hero-chevron-down" class="h-4 w-4" />
          <% else %>
            <.icon name="hero-chevron-right" class="h-4 w-4" />
          <% end %>
        </button>
        <.step_number_badge
          section_letter={@section_letter}
          step_index={@step_index}
          status={:completed}
        />
        <span class="font-semibold flex-1">{@step.title || @step.name}</span>
        <div class="flex items-center gap-2">
          <span class="w-8 h-8 rounded-full bg-success flex items-center justify-center">
            <.icon name="hero-check" class="h-4 w-4 text-success-content" />
          </span>
          <button type="button" class="btn btn-ghost btn-sm btn-square">
            <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
          </button>
        </div>
      </div>
      
    <!-- Expanded Details -->
      <%= if @is_expanded do %>
        <div class="px-4 pb-4 pl-16 space-y-3">
          <%= for block <- @step.blocks || [] do %>
            <.block_result_display
              block={block}
              block_execution={find_block_execution(@step_execution.block_executions || [], block.id)}
            />
          <% end %>

          <%= if length(@step_execution.signoffs || []) > 0 do %>
            <div class="pt-2 text-sm space-y-1">
              <%= for signoff <- @step_execution.signoffs do %>
                <div class="flex items-center gap-2">
                  <.icon name="hero-check-circle-solid" class="h-4 w-4 text-success" />
                  <span>Signoff by</span>
                  <span class="font-medium">{signoff.user.email}</span>
                  <span class="text-base-content/50">
                    {format_time_with_seconds(signoff.inserted_at)}
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Failed Step Card ──────────────────────────────────────────────────

  attr :step_execution, :map, required: true
  attr :step, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true
  attr :step_comments, :list, required: true
  attr :command_lifecycles, :map, default: %{}

  defp step_card_failed(assigns) do
    blocks = assigns.step.blocks || []
    block_executions = assigns.step_execution.block_executions || []

    assigns =
      assigns
      |> assign(:blocks, blocks)
      |> assign(:block_executions, block_executions)
      |> assign(:skip_form, to_form(%{}, as: :skip))

    ~H"""
    <div class="bg-base-100 rounded-lg border-2 border-error shadow-lg shadow-error/10">
      <!-- Step Header -->
      <div class="p-4 border-b border-error/20 bg-error/5">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <.step_number_badge
              section_letter={@section_letter}
              step_index={@step_index}
              status={:failed}
            />
            <div>
              <h3 class="font-bold text-lg">{@step.title || @step.name}</h3>
              <span class="text-sm text-base-content/60 font-mono">{@step.name}</span>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="retry_step"
              phx-value-step_id={@step_execution.id}
              class="btn btn-error btn-sm gap-1"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4" /> Retry Step
            </button>
            <div class="dropdown dropdown-end">
              <label tabindex="0" class="btn btn-ghost btn-sm">Skip</label>
              <div
                tabindex="0"
                class="dropdown-content z-[1] p-4 shadow-lg bg-base-100 rounded-lg w-72"
              >
                <.form
                  for={@skip_form}
                  id={"skip-step-form-#{@step_execution.id}"}
                  phx-submit="skip_step"
                >
                  <input type="hidden" name="skip[step_id]" value={@step_execution.id} />
                  <p class="text-sm mb-2">Reason for skipping:</p>
                  <.input
                    type="text"
                    field={@skip_form[:reason]}
                    id={"skip-step-reason-#{@step_execution.id}"}
                    placeholder="Enter skip reason..."
                    class="input input-bordered input-sm w-full mb-2"
                    required
                  />
                  <div class="flex justify-end gap-2">
                    <button type="submit" class="btn btn-ghost btn-sm">Skip Step</button>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Blocks -->
      <div class="p-4 space-y-4">
        <%= for block <- @blocks do %>
          <.block_execution_card
            block={block}
            block_execution={find_block_execution(@block_executions, block.id)}
            step_execution={@step_execution}
            step_status={@step_execution.status}
            command_lifecycles={@command_lifecycles}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # ── Pending Step Card ─────────────────────────────────────────────────

  attr :step_execution, :map, required: true
  attr :step, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true

  defp step_card_pending(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300">
      <!-- Header only - collapsed by default for pending -->
      <div class="p-3 flex items-center gap-3">
        <button type="button" class="text-base-content/30">
          <.icon name="hero-chevron-right" class="h-4 w-4" />
        </button>
        <.step_number_badge
          section_letter={@section_letter}
          step_index={@step_index}
          status={:pending}
        />
        <span class="font-semibold text-base-content/60 flex-1">{@step.title || @step.name}</span>
        <div class="flex items-center gap-2">
          <span class="w-8 h-8 rounded-full border-2 border-base-300 flex items-center justify-center">
            <.icon name="hero-check" class="h-4 w-4 text-base-content/20" />
          </span>
          <button type="button" class="btn btn-ghost btn-sm btn-square text-base-content/30">
            <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ── Skipped Step Card ─────────────────────────────────────────────────

  attr :step_execution, :map, required: true
  attr :step, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true

  defp step_card_skipped(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300">
      <div class="p-3 flex items-center gap-3">
        <button type="button" class="text-base-content/30">
          <.icon name="hero-chevron-right" class="h-4 w-4" />
        </button>
        <.step_number_badge
          section_letter={@section_letter}
          step_index={@step_index}
          status={:skipped}
        />
        <span class="font-semibold text-base-content/40 line-through flex-1">
          {@step.title || @step.name}
        </span>
        <span class="text-xs text-base-content/40">Skipped</span>
      </div>
    </div>
    """
  end

  # ── Block Preview (Disabled/Pending) ──────────────────────────────────

  attr :block, :map, required: true

  defp block_preview_disabled(assigns) do
    ~H"""
    <div class="p-3 rounded-lg bg-base-200/50 border border-base-300 opacity-60">
      <div class="flex items-center gap-2 text-sm text-base-content/50">
        <.block_type_icon type={@block.block_type} />
        <span class="capitalize">{format_block_type(@block.block_type)}</span>
        <%= if @block.content["label"] do %>
          <span class="text-base-content/40">- {@block.content["label"]}</span>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Block Result Display (Read-only for completed steps) ──────────────

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil

  defp block_result_display(assigns) do
    ~H"""
    <div class="p-3 rounded-lg bg-base-100 border border-base-200">
      <div class="flex items-center gap-2 text-sm mb-2">
        <.block_type_icon type={@block.block_type} />
        <span class="font-medium capitalize">{format_block_type(@block.block_type)}</span>
        <%= if @block.content["label"] do %>
          <span class="text-base-content/60">- {@block.content["label"]}</span>
        <% end %>
      </div>
      <div class="text-sm">
        <%= cond do %>
          <% @block.block_type in [
               :text_input,
               :number_input,
               :select_input,
               :checkbox_input,
               :timestamp_input,
               :duration_input,
               :attachment_input,
               :signature_input
             ] && @block_execution -> %>
            <span class="font-mono bg-base-200 px-2 py-1 rounded">
              {BlockExecution.display_value(@block_execution)}
            </span>
          <% @block.block_type == :telemetry_check && @block_execution -> %>
            <div class="flex items-center gap-2">
              <span class="font-mono">{@block.content["item"]}</span>
              <span>=</span>
              <span class="font-mono">{@block_execution.telemetry_reading["actual"]}</span>
              <%= if @block_execution.passed do %>
                <span class="badge badge-success badge-sm">PASS</span>
              <% else %>
                <span class="badge badge-error badge-sm">FAIL</span>
              <% end %>
            </div>
          <% @block.block_type == :telemetry_value && @block_execution -> %>
            <span class="font-mono">
              {@block_execution.telemetry_reading["value"]} {@block.content["unit"]}
            </span>
          <% true -> %>
            <span class="text-base-content/50">-</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_block_type(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  # ── Legacy section_progress (kept for reference, now replaced by nav_section) ──

  attr :section, :map, required: true
  attr :step_executions, :list, required: true
  attr :selected_id, :string, default: nil

  defp section_progress(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="text-xs font-semibold text-base-content/60 uppercase mb-2 px-2 flex items-center gap-2">
        <span>{@section.name}</span>
        <.section_progress_indicator step_executions={@step_executions} />
      </div>
      <div class="space-y-1">
        <%= for step_exec <- @step_executions do %>
          <div
            class={
              [
                "flex items-center gap-2 px-2 py-2 rounded-lg cursor-pointer transition-all duration-200",
                # Selected state
                step_exec.id == @selected_id && "ring-2 ring-primary/50",
                # Status-based styling
                step_exec.status == :completed && "bg-success/10 border-l-4 border-l-success",
                step_exec.status in [:active, :awaiting_signoff] &&
                  "bg-primary/10 border-l-4 border-l-primary shadow-sm",
                step_exec.status == :failed && "bg-error/10 border-l-4 border-l-error",
                step_exec.status == :skipped && "bg-base-200/50 border-l-4 border-l-base-300",
                step_exec.status in [:pending, :blocked] &&
                  "hover:bg-base-200 border-l-4 border-l-transparent"
              ]
            }
            phx-click="select_step"
            phx-value-id={step_exec.id}
          >
            <.step_status_icon status={step_exec.status} />
            <span class={[
              "text-sm truncate flex-1",
              step_exec.status == :completed && "text-success",
              step_exec.status in [:active, :awaiting_signoff] && "text-primary font-medium",
              step_exec.status == :failed && "text-error",
              step_exec.status == :skipped && "text-base-content/50 line-through"
            ]}>
              {step_exec.step.name}
            </span>
            <%= if step_exec.status in [:active, :awaiting_signoff] do %>
              <span class="relative flex h-2 w-2">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75">
                </span>
                <span class="relative inline-flex rounded-full h-2 w-2 bg-primary"></span>
              </span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :step_executions, :list, required: true

  defp section_progress_indicator(assigns) do
    completed = Enum.count(assigns.step_executions, &(&1.status == :completed))
    total = length(assigns.step_executions)

    assigns =
      assigns
      |> assign(:completed, completed)
      |> assign(:total, total)

    ~H"""
    <span class="text-xs font-mono text-base-content/40">
      ({@completed}/{@total})
    </span>
    """
  end

  attr :status, :atom, required: true

  defp step_status_icon(assigns) do
    ~H"""
    <%= case @status do %>
      <% :completed -> %>
        <span class="text-success"><.icon name="hero-check-circle-solid" class="h-4 w-4" /></span>
      <% :active -> %>
        <span class="text-primary"><.icon name="hero-play-circle-solid" class="h-4 w-4" /></span>
      <% :awaiting_signoff -> %>
        <span class="text-warning"><.icon name="hero-clock-solid" class="h-4 w-4" /></span>
      <% :failed -> %>
        <span class="text-error"><.icon name="hero-x-circle-solid" class="h-4 w-4" /></span>
      <% :skipped -> %>
        <span class="text-base-content/40">
          <.icon name="hero-minus-circle-solid" class="h-4 w-4" />
        </span>
      <% :blocked -> %>
        <span class="text-base-content/40">
          <.icon name="hero-lock-closed-solid" class="h-4 w-4" />
        </span>
      <% _ -> %>
        <span class="text-base-content/30">
          <.icon name="hero-ellipsis-horizontal-circle" class="h-4 w-4" />
        </span>
    <% end %>
    """
  end

  attr :step_execution, :map, required: true
  attr :user, :map, required: true
  attr :show_comment_form, :boolean, default: false
  attr :comments, :list, default: []

  defp active_step(assigns) do
    step = assigns.step_execution.step
    blocks = step.blocks || []
    block_executions = assigns.step_execution.block_executions || []
    signoffs = assigns.step_execution.signoffs || []

    assigns =
      assigns
      |> assign(:step, step)
      |> assign(:blocks, blocks)
      |> assign(:block_executions, block_executions)
      |> assign(:signoffs, signoffs)
      |> assign(:comment_form, to_form(%{}, as: :comment))

    ~H"""
    <div class="flex-1 overflow-y-auto">
      <!-- Step Header with Status-Based Styling -->
      <div class={[
        "p-4 border-b-2 transition-colors duration-300",
        @step_execution.status == :completed && "bg-success/5 border-b-success",
        @step_execution.status in [:active, :awaiting_signoff] && "bg-primary/5 border-b-primary",
        @step_execution.status == :failed && "bg-error/5 border-b-error",
        @step_execution.status not in [:completed, :active, :awaiting_signoff, :failed] &&
          "bg-base-100 border-b-base-300"
      ]}>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <.step_status_badge status={@step_execution.status} />
            <div>
              <h2 class="text-xl font-bold">{@step.title || @step.name}</h2>
              <span class="text-sm text-base-content/60 font-mono">{@step.name}</span>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <!-- Add Comment Button -->
            <button
              type="button"
              phx-click="toggle_comment_form"
              phx-value-step_id={@step_execution.id}
              class={[
                "btn btn-sm btn-ghost gap-1",
                @show_comment_form && "btn-active"
              ]}
            >
              <.icon name="hero-chat-bubble-left" class="h-4 w-4" />
              <span>Note</span>
            </button>

            <%= if @step_execution.status in [:active, :awaiting_signoff] do %>
              <div class="flex items-center gap-2 text-primary">
                <span class="relative flex h-3 w-3">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75">
                  </span>
                  <span class="relative inline-flex rounded-full h-3 w-3 bg-primary"></span>
                </span>
                <span class="text-sm font-medium uppercase tracking-wide">In Progress</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- Comment Form (Inline) -->
      <%= if @show_comment_form do %>
        <div class="p-4 bg-info/5 border-b border-info/20">
          <.form
            for={@comment_form}
            id={"active-step-comment-form-#{@step_execution.id}"}
            phx-submit="add_comment"
            class="flex gap-2"
          >
            <input type="hidden" name="comment[step_id]" value={@step_execution.id} />
            <.input
              type="text"
              field={@comment_form[:content]}
              id={"active-step-comment-content-#{@step_execution.id}"}
              placeholder="Add a note about this step..."
              class="input input-bordered flex-1 input-sm"
              autofocus
            />
            <button type="submit" class="btn btn-info btn-sm">
              <.icon name="hero-paper-airplane" class="h-4 w-4" />
            </button>
            <button type="button" phx-click="toggle_comment_form" class="btn btn-ghost btn-sm">
              Cancel
            </button>
          </.form>
        </div>
      <% end %>
      
    <!-- Existing Comments -->
      <%= if length(@comments) > 0 do %>
        <div class="p-4 bg-info/5 border-b border-info/20 space-y-2">
          <%= for comment <- Enum.reverse(@comments) do %>
            <div class="flex gap-3 p-2 bg-base-100 rounded-lg border-l-4 border-info">
              <.icon
                name="hero-chat-bubble-left-solid"
                class="h-4 w-4 text-info flex-shrink-0 mt-0.5"
              />
              <div class="flex-1 min-w-0">
                <p class="text-sm">{comment.content}</p>
                <div class="text-xs text-base-content/50 mt-1">
                  {comment.user.email} · {format_time_with_seconds(comment.inserted_at)}
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
      
    <!-- Blocks -->
      <div class="p-4 space-y-4">
        <%= for block <- @blocks do %>
          <.block_execution_card
            block={block}
            block_execution={find_block_execution(@block_executions, block.id)}
            step_execution={@step_execution}
            step_status={@step_execution.status}
          />
        <% end %>
      </div>
      
    <!-- Signoff / Complete Section -->
      <%= if @step_execution.status in [:active, :awaiting_signoff] do %>
        <div class="p-4 border-t-2 border-primary bg-primary/5">
          <%= if @step.requires_signoff do %>
            <.signoff_panel
              step={@step}
              step_execution={@step_execution}
              signoffs={@signoffs}
              user={@user}
            />
          <% else %>
            <%!-- No signoff required - just show Mark Complete button --%>
            <div class="flex items-center justify-between gap-4">
              <span class="text-base-content/60 text-sm">No signoff required for this step</span>
              <button
                type="button"
                phx-click="mark_step_complete"
                phx-value-step_id={@step_execution.id}
                class="btn btn-success btn-sm gap-2"
              >
                <.icon name="hero-check" class="h-4 w-4" /> Mark Complete
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp step_status_badge(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium",
      @status == :completed && "bg-success text-success-content",
      @status == :active && "bg-primary text-primary-content",
      @status == :awaiting_signoff && "bg-warning text-warning-content",
      @status == :failed && "bg-error text-error-content",
      @status == :skipped && "bg-base-300 text-base-content/60",
      @status == :pending && "bg-base-200 text-base-content/50",
      @status == :blocked && "bg-base-300 text-base-content/50"
    ]}>
      <.step_status_icon status={@status} />
      <span class="uppercase text-xs tracking-wide">{@status}</span>
    </div>
    """
  end

  defp find_block_execution(block_executions, block_id) do
    Enum.find(block_executions, &(&1.block_id == block_id))
  end

  defp step_snapshot(step_exec) do
    step = step_exec.step

    %{
      "name" => step.name,
      "title" => step.title,
      "blocks" =>
        Enum.map(step.blocks || [], fn block ->
          %{
            "block_type" => to_string(block.block_type),
            "content" => block.content
          }
        end)
    }
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true
  attr :command_lifecycles, :map, default: %{}

  defp block_execution_card(assigns) do
    # Only show header for callout-style blocks (note, caution, warning)
    show_header = assigns.block.block_type in [:note, :caution, :warning]
    assigns = assign(assigns, :show_header, show_header)

    ~H"""
    <div class={block_callout_classes(@block.block_type)}>
      <%= if @show_header do %>
        <div class="flex items-center gap-2 mb-1">
          <.block_type_icon type={@block.block_type} />
          <span class={["text-sm", block_header_color(@block.block_type)]}>
            {block_callout_label(@block)}
          </span>
        </div>
      <% end %>
      <.block_content
        block={@block}
        block_execution={@block_execution}
        step_execution={@step_execution}
        step_status={@step_status}
        command_lifecycles={@command_lifecycles}
      />
    </div>
    """
  end

  # Get callout label - use custom text or default
  defp block_callout_label(block) do
    block.content["label"] || block.content["text"] ||
      case block.block_type do
        :note -> "Note"
        :caution -> "Caution"
        :warning -> "Warning"
        _ -> ""
      end
  end

  # Colored callout classes for blocks (Epsilon3-style)
  @callout_classes %{
    note: "rounded px-3 py-2 bg-info/10",
    caution: "rounded px-3 py-2 bg-warning/10",
    warning: "rounded px-3 py-2 bg-error/10"
  }

  defp block_callout_classes(type) do
    Map.get(@callout_classes, type, "")
  end

  defp block_header_color(type) do
    case type do
      :note -> "text-info"
      :caution -> "text-warning"
      :warning -> "text-error"
      _ -> "text-base-content/60"
    end
  end

  defp input_classes(classes) do
    classes
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  attr :type, :atom, required: true

  @block_type_icons %{
    text: "hero-document-text",
    note: "hero-information-circle",
    caution: "hero-exclamation-triangle",
    warning: "hero-exclamation-circle",
    text_input: "hero-pencil-square",
    number_input: "hero-calculator",
    select_input: "hero-list-bullet",
    checkbox_input: "hero-check",
    timestamp_input: "hero-clock",
    duration_input: "hero-clock",
    attachment_input: "hero-paper-clip",
    signature_input: "hero-pencil",
    telemetry_value: "hero-signal",
    telemetry_check: "hero-check-circle",
    telemetry_wait: "hero-clock",
    command: "hero-command-line",
    command_sequence: "hero-queue-list",
    script: "hero-code-bracket"
  }

  defp block_type_icon(assigns) do
    icon = Map.get(@block_type_icons, assigns.type, "hero-cube")
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <.icon name={@icon} class="h-4 w-4" />
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true
  attr :command_lifecycles, :map, default: %{}

  defp block_content(assigns) do
    ~H"""
    <%= case @block.block_type do %>
      <% :text -> %>
        <p class="text-base-content/80">
          {@block.content["markdown"] || @block.content["text"]}
        </p>
      <% :note -> %>
        <p class="text-base-content">{@block.content["text"]}</p>
      <% :caution -> %>
        <p class="text-base-content">{@block.content["text"]}</p>
      <% :warning -> %>
        <p class="text-base-content">{@block.content["text"]}</p>
      <% :telemetry_value -> %>
        <.telemetry_value_display block={@block} block_execution={@block_execution} />
      <% :telemetry_check -> %>
        <.telemetry_check_display block={@block} block_execution={@block_execution} />
      <% :telemetry_wait -> %>
        <.telemetry_check_display block={@block} block_execution={@block_execution} />
      <% :text_input -> %>
        <.text_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :number_input -> %>
        <.number_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :select_input -> %>
        <.select_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :checkbox_input -> %>
        <.checkbox_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :timestamp_input -> %>
        <.timestamp_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :duration_input -> %>
        <.duration_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :attachment_input -> %>
        <.attachment_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :signature_input -> %>
        <.signature_input_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          step_status={@step_status}
        />
      <% :command -> %>
        <.command_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
          lifecycle={get_command_lifecycle(@block_execution, @command_lifecycles)}
        />
      <% :command_sequence -> %>
        <.command_sequence_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
        />
      <% :script -> %>
        <.script_block
          block={@block}
          block_execution={@block_execution}
          step_execution={@step_execution}
        />
      <% :wait -> %>
        <.wait_block block={@block} block_execution={@block_execution} />
      <% :wait_for -> %>
        <.wait_for_block block={@block} block_execution={@block_execution} />
      <% _ -> %>
        <div class="text-base-content/50 text-sm">
          Block type: {@block.block_type}
        </div>
    <% end %>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil

  defp telemetry_value_display(assigns) do
    has_value = assigns.block_execution && assigns.block_execution.telemetry_reading
    assigns = assign(assigns, :has_value, has_value)

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 transition-all duration-300",
      @has_value && "bg-base-100 border-primary/30",
      !@has_value && "bg-base-200 border-base-300 border-dashed"
    ]}>
      <!-- Header row -->
      <div class="flex items-start justify-between mb-3">
        <div>
          <%= if @block.content["label"] do %>
            <div class="text-sm font-medium text-base-content/80 mb-1">
              {@block.content["label"]}
            </div>
          <% end %>
          <div class="font-mono text-xs text-primary bg-primary/10 px-2 py-1 rounded inline-block">
            {@block.content["item"]}
          </div>
        </div>
        <%= if @has_value do %>
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
          </span>
        <% end %>
      </div>
      
    <!-- Value Display -->
      <div class="flex items-baseline gap-2">
        <%= if @has_value do %>
          <span class="text-4xl font-bold font-mono tracking-tight">
            {@block_execution.telemetry_reading["value"]}
          </span>
          <%= if @block.content["unit"] && @block.content["unit"] != "" do %>
            <span class="text-lg text-base-content/60">{@block.content["unit"]}</span>
          <% end %>
        <% else %>
          <span class="text-4xl font-bold font-mono text-base-content/30">--</span>
          <span class="text-sm text-base-content/40">Waiting for data...</span>
        <% end %>
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil

  defp telemetry_check_display(assigns) do
    status =
      cond do
        assigns.block_execution && assigns.block_execution.passed == true -> :passed
        assigns.block_execution && assigns.block_execution.passed == false -> :failed
        true -> :pending
      end

    assigns = assign(assigns, :status, status)

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 transition-all duration-300",
      @status == :passed && "bg-success/10 border-success",
      @status == :failed && "bg-error/10 border-error animate-pulse",
      @status == :pending && "bg-base-200 border-base-300 border-dashed"
    ]}>
      <!-- Check Condition -->
      <div class="flex items-center justify-between mb-4">
        <div class="font-mono text-sm">
          <span class="text-primary bg-primary/10 px-2 py-1 rounded">
            {@block.content["item"]}
          </span>
          <span class="mx-2 text-base-content/60">{@block.content["operator"]}</span>
          <span class="text-success bg-success/10 px-2 py-1 rounded font-bold">
            {@block.content["expected"]}
          </span>
        </div>
      </div>
      
    <!-- Result Display -->
      <div class="flex items-center gap-4">
        <!-- Status Badge (Large) -->
        <div class={[
          "flex items-center gap-2 px-4 py-2 rounded-lg font-bold text-lg",
          @status == :passed && "bg-success text-success-content",
          @status == :failed && "bg-error text-error-content",
          @status == :pending && "bg-base-300 text-base-content/50"
        ]}>
          <%= case @status do %>
            <% :passed -> %>
              <.icon name="hero-check-circle-solid" class="h-6 w-6" />
              <span>PASS</span>
            <% :failed -> %>
              <.icon name="hero-x-circle-solid" class="h-6 w-6" />
              <span>FAIL</span>
            <% :pending -> %>
              <.icon name="hero-clock" class="h-6 w-6" />
              <span>PENDING</span>
          <% end %>
        </div>
        
    <!-- Actual Value -->
        <%= if @block_execution && @block_execution.telemetry_reading do %>
          <div class="flex-1">
            <div class="text-xs text-base-content/60 uppercase tracking-wide">Actual Value</div>
            <div class={[
              "text-3xl font-bold font-mono",
              @status == :passed && "text-success",
              @status == :failed && "text-error"
            ]}>
              {@block_execution.telemetry_reading["actual"]}
            </div>
          </div>
        <% else %>
          <div class="flex-1">
            <div class="text-xs text-base-content/60 uppercase tracking-wide">Actual Value</div>
            <div class="text-3xl font-bold font-mono text-base-content/30">--</div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp text_input_block(assigns) do
    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    assigns = assign(assigns, :current_value, current_value)

    ~H"""
    <%!-- Epsilon3-style inline text input --%>
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <%!-- Completed: show value inline with check --%>
        <span class="font-mono px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
        <.icon name="hero-check-circle-solid" class="h-4 w-4 text-success" />
      <% else %>
        <%!-- Input field --%>
        <.input
          type="text"
          id={"input-#{@block.id}"}
          name="value"
          phx-blur="submit_input"
          phx-keydown="submit_input"
          phx-key="Enter"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "input input-bordered input-sm flex-1 min-w-[200px] max-w-md",
              @step_status in [:active, :awaiting_signoff] && "input-primary"
            ])
          }
          placeholder={@block.content["placeholder"] || "Enter value..."}
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp number_input_block(assigns) do
    %{
      min: min_val,
      max: max_val,
      unit: unit,
      pass_criteria: pass_criteria,
      current_value: current_value
    } =
      number_input_values(assigns.block, assigns.block_execution)

    validation_result = number_input_validation(current_value, pass_criteria, min_val, max_val)
    range_text = number_input_range_text(min_val, max_val)

    assigns =
      assigns
      |> assign(:min_val, min_val)
      |> assign(:max_val, max_val)
      |> assign(:unit, unit)
      |> assign(:range_text, range_text)
      |> assign(:current_value, current_value)
      |> assign(:validation_result, validation_result)

    ~H"""
    <%!-- Epsilon3-style inline input: Label = [value] Unit PASS (range) --%>
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <%!-- Completed: show value inline --%>
        <span class="font-mono text-lg font-bold px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
      <% else %>
        <%!-- Input field --%>
        <.input
          type="number"
          id={"input-#{@block.id}"}
          name="value"
          phx-blur="submit_input"
          phx-keydown="submit_input"
          phx-key="Enter"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "input input-bordered input-sm w-24 font-mono text-center",
              @step_status in [:active, :awaiting_signoff] && "input-primary"
            ])
          }
          min={@min_val}
          max={@max_val}
          placeholder="--"
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>

      <%= if @unit do %>
        <span class="text-base-content/60">{@unit}</span>
      <% end %>

      <%= if @validation_result do %>
        <span class={[
          "font-bold text-sm px-2 py-0.5 rounded",
          @validation_result == :pass && "bg-success/20 text-success",
          @validation_result == :fail && "bg-error/20 text-error"
        ]}>
          {if @validation_result == :pass, do: "PASS", else: "FAIL"}
        </span>
      <% end %>

      <%= if @range_text do %>
        <span class="text-sm text-base-content/50">{@range_text}</span>
      <% end %>
    </div>
    """
  end

  # Simple pass/fail evaluation for number inputs
  defp evaluate_pass_criteria(value, min_val, max_val) do
    case to_number(value) do
      {:ok, val} -> pass_fail_by_bounds(val, min_val, max_val)
      :error -> nil
    end
  end

  defp to_number(value) when is_number(value), do: {:ok, value}

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> {:ok, num}
      _ -> :error
    end
  end

  defp to_number(_value), do: :error

  defp pass_fail_by_bounds(value, min_val, max_val) do
    min_ok = is_nil(min_val) or value >= min_val
    max_ok = is_nil(max_val) or value <= max_val

    if min_ok and max_ok, do: :pass, else: :fail
  end

  defp number_input_values(block, block_execution) do
    %{
      min: block.content["min"],
      max: block.content["max"],
      unit: block.content["unit"],
      pass_criteria: block.content["pass_criteria"],
      current_value: block_execution && BlockExecution.display_value(block_execution)
    }
  end

  defp number_input_validation(nil, _pass_criteria, _min_val, _max_val), do: nil
  defp number_input_validation(_value, nil, _min_val, _max_val), do: :pass

  defp number_input_validation(value, _pass_criteria, min_val, max_val) do
    evaluate_pass_criteria(value, min_val, max_val)
  end

  defp number_input_range_text(min_val, max_val) do
    cond do
      min_val && max_val -> "(#{min_val} - #{max_val})"
      min_val -> "(>= #{min_val})"
      max_val -> "(<= #{max_val})"
      true -> nil
    end
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp select_input_block(assigns) do
    options = assigns.block.content["options"] || []

    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    assigns = assign(assigns, :options, options)
    assigns = assign(assigns, :current_value, current_value)

    ~H"""
    <%!-- Epsilon3-style inline select input --%>
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <%!-- Completed: show selected value --%>
        <span class="font-mono text-lg font-bold px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
      <% else %>
        <%!-- Select dropdown --%>
        <.input
          type="select"
          id={"input-#{@block.id}"}
          name="value"
          options={@options}
          prompt="Select..."
          phx-change="submit_select"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "select select-bordered select-sm min-w-[150px]",
              @step_status in [:active, :awaiting_signoff] && "select-primary"
            ])
          }
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp checkbox_input_block(assigns) do
    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    assigns = assign(assigns, :current_value, current_value)

    ~H"""
    <div class="flex items-center gap-3 flex-wrap">
      <%= if is_boolean(@current_value) do %>
        <span class="font-medium text-base-content">
          {@block.content["label"] || @block.name}
        </span>
        <span class={[
          "px-2 py-0.5 rounded text-sm",
          @current_value && "bg-success/20 text-success",
          !@current_value && "bg-base-200 text-base-content/60"
        ]}>
          {if @current_value, do: "Checked", else: "Unchecked"}
        </span>
      <% else %>
        <.input
          type="checkbox"
          id={"input-#{@block.id}"}
          name="value"
          label={@block.content["label"] || @block.name}
          value={false}
          phx-change="submit_checkbox"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp timestamp_input_block(assigns) do
    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    assigns = assign(assigns, :current_value, current_value)

    ~H"""
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <span class="font-mono px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
        <.icon name="hero-check-circle-solid" class="h-4 w-4 text-success" />
      <% else %>
        <.input
          type="datetime-local"
          id={"input-#{@block.id}"}
          name="value"
          phx-blur="submit_input"
          phx-keydown="submit_input"
          phx-key="Enter"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "input input-bordered input-sm",
              @step_status in [:active, :awaiting_signoff] && "input-primary"
            ])
          }
          placeholder={@block.content["placeholder"] || "Select timestamp"}
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp duration_input_block(assigns) do
    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    unit = assigns.block.content["unit"] || "seconds"

    assigns =
      assigns
      |> assign(:current_value, current_value)
      |> assign(:unit, unit)

    ~H"""
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <span class="font-mono text-lg font-bold px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
      <% else %>
        <.input
          type="number"
          id={"input-#{@block.id}"}
          name="value"
          phx-blur="submit_input"
          phx-keydown="submit_input"
          phx-key="Enter"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "input input-bordered input-sm w-28 font-mono text-center",
              @step_status in [:active, :awaiting_signoff] && "input-primary"
            ])
          }
          placeholder="--"
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>

      <span class="text-base-content/60">{@unit}</span>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp attachment_input_block(assigns) do
    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    assigns = assign(assigns, :current_value, current_value)

    ~H"""
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <span class="font-mono px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
        <.icon name="hero-check-circle-solid" class="h-4 w-4 text-success" />
      <% else %>
        <.input
          type="text"
          id={"input-#{@block.id}"}
          name="value"
          phx-blur="submit_input"
          phx-keydown="submit_input"
          phx-key="Enter"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "input input-bordered input-sm flex-1 min-w-[220px]",
              @step_status in [:active, :awaiting_signoff] && "input-primary"
            ])
          }
          placeholder={@block.content["placeholder"] || "Add attachment reference"}
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :step_status, :atom, required: true

  defp signature_input_block(assigns) do
    current_value =
      if assigns.block_execution,
        do: BlockExecution.display_value(assigns.block_execution),
        else: nil

    assigns = assign(assigns, :current_value, current_value)

    ~H"""
    <div class="flex items-center gap-3 flex-wrap">
      <span class="font-medium text-base-content">{@block.content["label"] || @block.name} =</span>

      <%= if @current_value do %>
        <span class="font-mono px-2 py-0.5 bg-base-200 rounded">
          {@current_value}
        </span>
        <.icon name="hero-check-circle-solid" class="h-4 w-4 text-success" />
      <% else %>
        <.input
          type="text"
          id={"input-#{@block.id}"}
          name="value"
          phx-blur="submit_input"
          phx-keydown="submit_input"
          phx-key="Enter"
          phx-value-block_id={@block.id}
          phx-value-step_id={@step_execution.id}
          class={
            input_classes([
              "input input-bordered input-sm flex-1 min-w-[200px]",
              @step_status in [:active, :awaiting_signoff] && "input-primary"
            ])
          }
          placeholder={@block.content["placeholder"] || "Signed by..."}
          disabled={@step_status not in [:active, :awaiting_signoff]}
        />
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true

  defp command_sequence_block(assigns) do
    commands = assigns.block.content["commands"] || []
    status = assigns.block_execution && assigns.block_execution.status
    assigns = assign(assigns, :commands, commands)
    assigns = assign(assigns, :status, status)

    ~H"""
    <div class="rounded-lg border-2 p-4 transition-all duration-300 bg-base-100 border-base-300">
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <.icon name="hero-queue-list" class="h-5 w-5 text-warning" />
          <span class="text-xs font-medium uppercase tracking-wide text-base-content/60">
            Command Sequence
          </span>
        </div>
        <span class="text-xs text-base-content/60">{length(@commands)} commands</span>
      </div>

      <%= if @status == :completed do %>
        <div class="flex items-center gap-2 text-success">
          <.icon name="hero-check-circle-solid" class="h-5 w-5" />
          <span class="font-medium">Sequence Queued</span>
        </div>
      <% else %>
        <button
          type="button"
          phx-click="send_command"
          phx-value-step_id={@step_execution.id}
          phx-value-block_id={@block.id}
          class="btn btn-warning gap-2"
        >
          <.icon name="hero-paper-airplane" class="h-4 w-4" /> Send Sequence
        </button>
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true
  attr :lifecycle, :list, default: []

  defp command_block(assigns) do
    # Use lifecycle data to determine actual command status when available
    # The block_execution is marked :completed when queued, but the command
    # may still be in transit (queued -> executing -> sent)
    has_lifecycle = Enum.any?(assigns.lifecycle)
    status = command_block_status(assigns.lifecycle, assigns.block_execution)

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:has_lifecycle, has_lifecycle)

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 transition-all duration-300",
      @status == :sent && "bg-success/10 border-success",
      @status == :failed && "bg-error/10 border-error",
      @status == :running && "bg-primary/10 border-primary animate-pulse",
      @status == :queued && "bg-info/10 border-info",
      @status == :ready && "bg-warning/5 border-warning"
    ]}>
      <!-- Command Header -->
      <div class="flex items-center gap-2 mb-3">
        <.icon name="hero-command-line" class="h-5 w-5 text-warning" />
        <span class="text-xs font-medium uppercase tracking-wide text-base-content/60">Command</span>
      </div>
      
    <!-- Command Name -->
      <div class="font-mono text-lg font-bold text-warning bg-warning/10 px-3 py-2 rounded mb-4">
        {@block.content["command_name"]}
      </div>
      
    <!-- Command Lifecycle Timeline -->
      <%= if @has_lifecycle do %>
        <.command_lifecycle_timeline lifecycle={@lifecycle} />
      <% end %>
      
    <!-- Action/Status -->
      <div class="flex items-center justify-between">
        <%= case @status do %>
          <% :sent -> %>
            <div class="flex items-center gap-2 text-success">
              <.icon name="hero-check-circle-solid" class="h-5 w-5" />
              <span class="font-medium">Command Sent</span>
            </div>
          <% :failed -> %>
            <div class="flex items-center gap-2 text-error">
              <.icon name="hero-x-circle-solid" class="h-5 w-5" />
              <span class="font-medium">Command Failed</span>
            </div>
            <button
              type="button"
              phx-click="retry_block"
              phx-value-step_id={@step_execution.id}
              phx-value-block_id={@block.id}
              class="btn btn-error btn-sm gap-1"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4" /> Retry
            </button>
          <% :running -> %>
            <div class="flex items-center gap-2 text-primary">
              <span class="loading loading-spinner loading-sm"></span>
              <span class="font-medium">Dispatching...</span>
            </div>
          <% :queued -> %>
            <div class="flex items-center gap-2 text-info">
              <.icon name="hero-clock" class="h-5 w-5" />
              <span class="font-medium">Command Queued</span>
            </div>
          <% :ready -> %>
            <div class="text-sm text-base-content/60">Ready to send</div>
            <button
              type="button"
              phx-click="send_command"
              phx-value-step_id={@step_execution.id}
              phx-value-block_id={@block.id}
              class="btn btn-warning gap-2"
            >
              <.icon name="hero-paper-airplane" class="h-4 w-4" /> Send Command
            </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp command_block_status([], block_execution) do
    status_from_execution(block_execution)
  end

  defp command_block_status(lifecycle, _block_execution) do
    status_from_lifecycle(lifecycle)
  end

  defp status_from_lifecycle(lifecycle) do
    last_event = List.last(lifecycle)

    case last_event.state do
      :sent -> :sent
      :failed -> :failed
      :cancelled -> :failed
      :expired -> :failed
      :executing -> :running
      :queued -> :queued
      _ -> :ready
    end
  end

  defp status_from_execution(nil), do: :ready

  defp status_from_execution(%{status: :completed}), do: :sent
  defp status_from_execution(%{status: :failed}), do: :failed
  defp status_from_execution(%{status: status}) when status in [:active, :running], do: :running
  defp status_from_execution(_block_execution), do: :ready

  # ── Command Lifecycle Timeline ──────────────────────────────────────────────

  attr :lifecycle, :list, required: true

  defp command_lifecycle_timeline(assigns) do
    ~H"""
    <div class="mb-4 py-2 px-3 bg-base-200/50 rounded-lg">
      <div class="text-xs font-medium text-base-content/60 mb-2">Command Timeline</div>
      <div class="flex items-center gap-2 flex-wrap">
        <%= for {event, index} <- Enum.with_index(@lifecycle) do %>
          <%= if index > 0 do %>
            <.icon name="hero-arrow-right" class="h-3 w-3 text-base-content/30" />
          <% end %>
          <.lifecycle_badge event={event} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  defp lifecycle_badge(assigns) do
    badge_class =
      case assigns.event.state do
        :queued -> "bg-yellow-100 text-yellow-800 border-yellow-300"
        :executing -> "bg-blue-100 text-blue-800 border-blue-300"
        :sent -> "bg-green-100 text-green-800 border-green-300"
        :failed -> "bg-red-100 text-red-800 border-red-300"
        :cancelled -> "bg-gray-100 text-gray-800 border-gray-300"
        :expired -> "bg-orange-100 text-orange-800 border-orange-300"
        _ -> "bg-gray-100 text-gray-600 border-gray-300"
      end

    assigns = assign(assigns, :badge_class, badge_class)

    ~H"""
    <div class={[
      "inline-flex items-center gap-1.5 px-2 py-1 rounded border text-xs font-medium",
      @badge_class
    ]}>
      <.lifecycle_state_icon state={@event.state} />
      <span>{format_lifecycle_state(@event.state)}</span>
      <span class="text-base-content/50 font-normal">{format_lifecycle_time(@event.timestamp)}</span>
    </div>
    """
  end

  attr :state, :atom, required: true

  defp lifecycle_state_icon(assigns) do
    icon =
      case assigns.state do
        :queued -> "hero-clock"
        :executing -> "hero-arrow-path"
        :sent -> "hero-check-circle"
        :failed -> "hero-x-circle"
        :cancelled -> "hero-no-symbol"
        :expired -> "hero-exclamation-triangle"
        _ -> "hero-question-mark-circle"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <.icon name={@icon} class="h-3.5 w-3.5" />
    """
  end

  defp format_lifecycle_state(:queued), do: "Queued"
  defp format_lifecycle_state(:executing), do: "Executing"
  defp format_lifecycle_state(:sent), do: "Sent"
  defp format_lifecycle_state(:failed), do: "Failed"
  defp format_lifecycle_state(:cancelled), do: "Cancelled"
  defp format_lifecycle_state(:expired), do: "Expired"
  defp format_lifecycle_state(_), do: "Unknown"

  defp format_lifecycle_time(nil), do: ""

  defp format_lifecycle_time(timestamp) do
    Calendar.strftime(timestamp, "%H:%M:%S")
  end

  # ── Script Block ─────────────────────────────────────────────────────────────

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil
  attr :step_execution, :map, required: true

  defp script_block(assigns) do
    status =
      cond do
        assigns.block_execution && assigns.block_execution.status == :completed ->
          :completed

        assigns.block_execution && assigns.block_execution.status == :failed ->
          :failed

        assigns.block_execution && assigns.block_execution.status in [:active, :running] ->
          :running

        true ->
          :pending
      end

    timeout = assigns.block.content["timeout_seconds"] || 60

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:timeout, timeout)

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 transition-all duration-300",
      @status == :completed && "bg-success/10 border-success",
      @status == :failed && "bg-error/10 border-error",
      @status == :running && "bg-primary/10 border-primary animate-pulse",
      @status == :pending && "bg-base-200 border-base-300"
    ]}>
      <!-- Script Header -->
      <div class="flex items-center gap-2 mb-3">
        <.icon name="hero-code-bracket" class="h-5 w-5 text-primary" />
        <span class="text-xs font-medium uppercase tracking-wide text-base-content/60">
          Lua Script
        </span>
        <span class="text-xs text-base-content/40 ml-auto">Timeout: {@timeout}s</span>
      </div>
      
    <!-- Script Preview (collapsed) -->
      <div class="font-mono text-sm bg-base-300 rounded p-3 mb-3 max-h-24 overflow-hidden relative">
        <pre class="text-base-content/80 whitespace-pre-wrap">{String.slice(@block.content["script"] || "", 0, 200)}</pre>
        <%= if String.length(@block.content["script"] || "") > 200 do %>
          <div class="absolute bottom-0 left-0 right-0 h-8 bg-gradient-to-t from-base-300 to-transparent">
          </div>
        <% end %>
      </div>
      
    <!-- Status/Result -->
      <div class="flex items-center justify-between">
        <%= case @status do %>
          <% :completed -> %>
            <div class="flex items-center gap-2 text-success">
              <.icon name="hero-check-circle-solid" class="h-5 w-5" />
              <span class="font-medium">Script Completed</span>
            </div>
            <%= if @block_execution && @block_execution.value do %>
              <div class="text-xs font-mono text-base-content/60">
                Result: {inspect(@block_execution.value["script_result"])}
              </div>
            <% end %>
          <% :failed -> %>
            <div class="flex items-center gap-2 text-error">
              <.icon name="hero-x-circle-solid" class="h-5 w-5" />
              <span class="font-medium">Script Failed</span>
            </div>
            <div class="flex items-center gap-2">
              <%= if @block_execution && @block_execution.validation_message do %>
                <div class="text-xs text-error">
                  {@block_execution.validation_message}
                </div>
              <% end %>
              <button
                type="button"
                phx-click="retry_block"
                phx-value-step_id={@step_execution.id}
                phx-value-block_id={@block.id}
                class="btn btn-error btn-sm gap-1"
              >
                <.icon name="hero-arrow-path" class="h-4 w-4" /> Retry
              </button>
            </div>
          <% :running -> %>
            <div class="flex items-center gap-2 text-primary">
              <span class="loading loading-spinner loading-sm"></span>
              <span class="font-medium">Running Script...</span>
            </div>
          <% :pending -> %>
            <div class="text-sm text-base-content/60">
              Will run automatically
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Wait Block ─────────────────────────────────────────────────────────────

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil

  defp wait_block(assigns) do
    status = wait_block_status(assigns.block_execution)
    duration = assigns.block.content["duration"] || assigns.block.content["duration_ms"] || 0

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:duration, duration)

    assigns = assign(assigns, :icon_class, wait_block_icon_class(status))

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 transition-all duration-300",
      @status == :completed && "bg-success/10 border-success",
      @status == :running && "bg-primary/10 border-primary",
      @status == :pending && "bg-base-200 border-base-300"
    ]}>
      <div class="flex items-center gap-3">
        <.icon name="hero-clock" class={@icon_class} />
        <div>
          <span class="text-sm font-medium">Wait</span>
          <span class="text-lg font-bold font-mono ml-2">{@duration}ms</span>
        </div>
        <%= if @status == :completed do %>
          <.icon name="hero-check-circle-solid" class="h-5 w-5 text-success ml-auto" />
        <% end %>
      </div>
    </div>
    """
  end

  defp wait_block_status(nil), do: :pending
  defp wait_block_status(%{status: :completed}), do: :completed
  defp wait_block_status(%{status: status}) when status in [:active, :running], do: :running
  defp wait_block_status(_block_execution), do: :pending

  defp wait_block_icon_class(:running), do: "h-6 w-6 animate-spin text-primary"
  defp wait_block_icon_class(:completed), do: "h-6 w-6 text-success"
  defp wait_block_icon_class(_status), do: "h-6 w-6 text-base-content/40"

  # ── Wait For Block ─────────────────────────────────────────────────────────

  attr :block, :map, required: true
  attr :block_execution, :map, default: nil

  defp wait_for_block(assigns) do
    status = wait_for_status(assigns.block_execution)
    item = assigns.block.content["item"]
    operator = assigns.block.content["operator"] || "=="
    expected = assigns.block.content["value"] || assigns.block.content["expected"]
    timeout_ms = wait_for_timeout(assigns.block)

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:item, item)
      |> assign(:operator, operator)
      |> assign(:expected, expected)
      |> assign(:timeout_ms, timeout_ms)

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 transition-all duration-300",
      @status == :satisfied && "bg-success/10 border-success",
      @status == :timeout && "bg-error/10 border-error",
      @status == :waiting && "bg-primary/10 border-primary animate-pulse",
      @status == :pending && "bg-base-200 border-base-300"
    ]}>
      <div class="flex items-center gap-2 mb-3">
        <.icon name="hero-clock" class="h-5 w-5 text-primary" />
        <span class="text-xs font-medium uppercase tracking-wide text-base-content/60">
          Wait For Condition
        </span>
        <span class="text-xs text-base-content/40 ml-auto">Timeout: {div(@timeout_ms, 1000)}s</span>
      </div>
      
    <!-- Condition Display -->
      <div class="flex items-center gap-2 font-mono text-sm bg-base-300 rounded px-3 py-2 mb-3">
        <span class="text-primary">{@item}</span>
        <span class="text-base-content/60">{@operator}</span>
        <span class="text-success">{inspect(@expected)}</span>
      </div>
      
    <!-- Status -->
      <div class="flex items-center justify-between">
        <%= case @status do %>
          <% :satisfied -> %>
            <div class="flex items-center gap-2 text-success">
              <.icon name="hero-check-circle-solid" class="h-5 w-5" />
              <span class="font-medium">Condition Satisfied</span>
            </div>
          <% :timeout -> %>
            <div class="flex items-center gap-2 text-error">
              <.icon name="hero-x-circle-solid" class="h-5 w-5" />
              <span class="font-medium">Timeout - Condition Not Met</span>
            </div>
          <% :waiting -> %>
            <div class="flex items-center gap-2 text-primary">
              <span class="loading loading-spinner loading-sm"></span>
              <span class="font-medium">Waiting for condition...</span>
            </div>
          <% :pending -> %>
            <div class="text-sm text-base-content/60">
              Will wait for condition
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp wait_for_status(nil), do: :pending
  defp wait_for_status(%{status: :completed}), do: :satisfied
  defp wait_for_status(%{status: :failed}), do: :timeout
  defp wait_for_status(%{status: status}) when status in [:active, :running], do: :waiting
  defp wait_for_status(_block_execution), do: :pending

  defp wait_for_timeout(block) do
    block.content["timeout"] || block.content["timeout_ms"] || 30_000
  end

  attr :step, :map, required: true
  attr :step_execution, :map, required: true
  attr :signoffs, :list, required: true
  attr :user, :map, required: true

  defp signoff_panel(assigns) do
    required_roles = assigns.step.required_roles || ["operator"]
    signed_roles = Enum.map(assigns.signoffs, & &1.role)
    remaining_roles = required_roles -- signed_roles

    assigns =
      assigns
      |> assign(:required_roles, required_roles)
      |> assign(:signed_roles, signed_roles)
      |> assign(:remaining_roles, remaining_roles)

    ~H"""
    <div class="space-y-3">
      <!-- Signoff buttons for remaining roles -->
      <%= if length(@remaining_roles) > 0 do %>
        <div class="flex items-center gap-2 flex-wrap">
          <%= for role <- @remaining_roles do %>
            <button
              type="button"
              phx-click="sign_off"
              phx-value-step_id={@step_execution.id}
              phx-value-role={role}
              class="btn btn-sm btn-outline gap-2"
            >
              <.icon name="hero-check-circle" class="h-4 w-4" />
              <span class="capitalize">Sign off as {role}</span>
            </button>
          <% end %>
        </div>
      <% else %>
        <div class="flex items-center justify-between gap-4 p-3 bg-success/10 rounded-lg">
          <div class="flex items-center gap-2">
            <.icon name="hero-check-circle-solid" class="h-5 w-5 text-success" />
            <span class="text-success font-medium">All signoffs complete</span>
          </div>
          <button
            type="button"
            phx-click="mark_step_complete"
            phx-value-step_id={@step_execution.id}
            class="btn btn-success btn-sm gap-2"
          >
            <.icon name="hero-check" class="h-4 w-4" /> Mark Complete
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp short_email(nil), do: "Unknown"

  defp short_email(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
  end

  defp format_time_with_seconds(nil), do: "--:--:--"

  defp format_time_with_seconds(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end
end
