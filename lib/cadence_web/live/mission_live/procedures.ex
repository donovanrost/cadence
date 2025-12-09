defmodule CadenceWeb.MissionLive.Procedures do
  @moduledoc """
  LiveView for managing and executing procedures within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.Procedure
  alias Cadence.Procedures.Runtime

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        # Subscribe to procedure execution updates
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:procedures")
        end

        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :index, params) do
    mission = socket.assigns.mission

    # Parse tag filters from URL params
    selected_tags = parse_tag_params(params["tags"])

    # Get available tags for filter dropdown
    available_tags = Procedures.list_tags(mission.organization_id, mission_id: mission.id)

    # List procedures with optional tag filter
    procedures =
      Procedures.list_procedures(
        mission.organization_id,
        mission_id: mission.id,
        tags: selected_tags
      )

    # Get active execution counts
    execution_counts = get_execution_counts(mission.id)
    active_executions = get_active_executions(mission.id)

    socket
    |> assign(:page_title, "Procedures")
    |> assign(:procedures, procedures)
    |> assign(:procedure, nil)
    |> assign(:execution_counts, execution_counts)
    |> assign(:active_executions, active_executions)
    |> assign(:selected_procedure, nil)
    |> assign(:available_tags, available_tags)
    |> assign(:selected_tags, selected_tags)
    |> assign(:show_import_modal, false)
    |> assign(:import_form, to_form(%{"json" => "", "name" => ""}))
    |> assign(:import_preview, nil)
  end

  defp parse_tag_params(nil), do: []
  defp parse_tag_params(""), do: []

  defp parse_tag_params(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp apply_action(socket, :new, _params) do
    socket = apply_action(socket, :index, %{})

    socket
    |> assign(:page_title, "New Procedure")
    |> assign(:procedure, %Procedure{type: :dag})
  end

  defp apply_action(socket, :edit, %{"procedure_id" => procedure_id}) do
    socket = apply_action(socket, :index, %{})
    mission = socket.assigns.mission

    case Procedures.get_procedure(procedure_id) do
      nil ->
        socket
        |> put_flash(:error, "Procedure not found")
        |> push_patch(to: ~p"/missions/#{mission}/procedures")

      procedure when procedure.mission_id == mission.id ->
        socket
        |> assign(:page_title, "Edit Procedure")
        |> assign(:procedure, procedure)

      _procedure ->
        socket
        |> put_flash(:error, "Procedure not found in this mission")
        |> push_patch(to: ~p"/missions/#{mission}/procedures")
    end
  end

  defp apply_action(socket, :show, %{"procedure_id" => procedure_id}) do
    socket = apply_action(socket, :index, %{})
    mission = socket.assigns.mission

    case Procedures.get_procedure(procedure_id) do
      nil ->
        socket
        |> put_flash(:error, "Procedure not found")
        |> push_patch(to: ~p"/missions/#{mission}/procedures")

      procedure when procedure.mission_id == mission.id ->
        # Load versions and executions for this procedure
        versions = Procedures.list_versions(procedure.id)
        executions = Procedures.list_executions(procedure_id: procedure.id, limit: 10)

        # Load approval status for in_review versions
        versions_with_status =
          Enum.map(versions, fn version ->
            if version.status == :in_review do
              Map.put(version, :approval_status, Procedures.get_approval_status(version))
            else
              version
            end
          end)

        socket
        |> assign(:page_title, procedure.name)
        |> assign(:selected_procedure, procedure)
        |> assign(:versions, versions_with_status)
        |> assign(:recent_executions, executions)

      _procedure ->
        socket
        |> put_flash(:error, "Procedure not found in this mission")
        |> push_patch(to: ~p"/missions/#{mission}/procedures")
    end
  end

  defp apply_action(socket, :execute, %{"procedure_id" => procedure_id}) do
    socket = apply_action(socket, :show, %{"procedure_id" => procedure_id})
    procedure = socket.assigns.selected_procedure

    # Get the current version's parameter schema
    parameters_schema =
      if procedure.current_version_id do
        case Procedures.get_version(procedure.current_version_id) do
          nil -> nil
          version -> version.parameters_schema
        end
      else
        nil
      end

    socket
    |> assign(:page_title, "Execute #{procedure.name}")
    |> assign(:execution_params, %{})
    |> assign(:parameters_schema, parameters_schema)
  end

  defp get_execution_counts(mission_id) do
    Runtime.get_execution_counts(mission_id)
  end

  defp get_active_executions(mission_id) do
    Runtime.list_active_executions(mission_id)
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    mission = socket.assigns.mission
    selected_tags = socket.assigns.selected_tags

    new_tags =
      if tag in selected_tags do
        List.delete(selected_tags, tag)
      else
        [tag | selected_tags]
      end

    # Build URL with new tags
    path =
      if new_tags == [] do
        ~p"/missions/#{mission}/procedures"
      else
        ~p"/missions/#{mission}/procedures?tags=#{Enum.join(new_tags, ",")}"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("clear_tags", _params, socket) do
    mission = socket.assigns.mission
    {:noreply, push_patch(socket, to: ~p"/missions/#{mission}/procedures")}
  end

  def handle_event("execute", %{"id" => procedure_id}, socket) do
    mission = socket.assigns.mission

    {:noreply,
     push_patch(socket, to: ~p"/missions/#{mission}/procedures/#{procedure_id}/execute")}
  end

  def handle_event("start_execution", %{"procedure_id" => procedure_id} = params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    # Parse parameters from form
    parameters = params["parameters"] || %{}

    case Bodyguard.permit(Cadence.Missions.Policy, :send_command, scope, mission) do
      :ok ->
        case Runtime.start_execution(mission.id, procedure_id,
               parameters: parameters,
               user_id: scope.user.id
             ) do
          {:ok, _execution} ->
            {:noreply,
             socket
             |> put_flash(:info, "Procedure execution started")
             |> push_patch(to: ~p"/missions/#{mission}/procedures/#{procedure_id}")}

          {:error, :mission_not_running} ->
            {:noreply, put_flash(socket, :error, "Mission is not currently active")}

          {:error, :at_concurrency_limit} ->
            {:noreply, put_flash(socket, :error, "Too many procedures running. Please wait.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to execute procedures")}
    end
  end

  def handle_event("pause_execution", %{"id" => execution_id}, socket) do
    mission = socket.assigns.mission

    case Runtime.pause_execution(mission.id, execution_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Execution paused")}

      {:error, :mission_not_running} ->
        {:noreply, put_flash(socket, :error, "Mission is not currently active")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to pause: #{inspect(reason)}")}
    end
  end

  def handle_event("resume_execution", %{"id" => execution_id}, socket) do
    mission = socket.assigns.mission

    case Runtime.resume_execution(mission.id, execution_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Execution resumed")}

      {:error, :mission_not_running} ->
        {:noreply, put_flash(socket, :error, "Mission is not currently active")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resume: #{inspect(reason)}")}
    end
  end

  def handle_event("abort_execution", %{"id" => execution_id}, socket) do
    mission = socket.assigns.mission

    case Runtime.abort_execution(mission.id, execution_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Execution aborted")}

      {:error, :mission_not_running} ->
        {:noreply, put_flash(socket, :error, "Mission is not currently active")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to abort: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_for_review", %{"version_id" => version_id}, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        version = Procedures.get_version!(version_id)

        case Procedures.submit_for_review(version, scope.user.id) do
          {:ok, _version} ->
            reload_versions_and_procedure(socket, "Version submitted for review")

          {:error, :invalid_status} ->
            {:noreply, put_flash(socket, :error, "Can only submit draft versions")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to submit: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to submit versions")}
    end
  end

  def handle_event("withdraw_submission", %{"version_id" => version_id}, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        version = Procedures.get_version!(version_id)

        case Procedures.withdraw_submission(version, scope.user.id) do
          {:ok, _version} ->
            reload_versions_and_procedure(socket, "Submission withdrawn")

          {:error, :invalid_status} ->
            {:noreply, put_flash(socket, :error, "Can only withdraw versions in review")}

          {:error, :not_author} ->
            {:noreply, put_flash(socket, :error, "Only the author can withdraw a submission")}

          {:error, :withdrawal_not_allowed} ->
            {:noreply, put_flash(socket, :error, "Withdrawal is not allowed for this mission")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to withdraw: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to withdraw submissions")}
    end
  end

  def handle_event(
        "add_approval",
        %{"version_id" => version_id, "decision" => decision} = params,
        socket
      ) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        version = Procedures.get_version!(version_id)
        decision_atom = String.to_existing_atom(decision)
        comment = params["comment"]

        case Procedures.add_approval(version, scope.user.id, decision_atom, comment: comment) do
          {:ok, %{version: _version}} ->
            message =
              if decision_atom == :approved,
                do: "Approval recorded",
                else: "Rejection recorded - version returned to draft"

            reload_versions_and_procedure(socket, message)

          {:error, :invalid_status} ->
            {:noreply, put_flash(socket, :error, "Can only review versions in review status")}

          {:error, :cannot_approve_own_work} ->
            {:noreply, put_flash(socket, :error, "You cannot approve your own work")}

          {:error, :already_submitted_decision} ->
            {:noreply, put_flash(socket, :error, "You have already submitted a decision")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to add approval: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve versions")}
    end
  end

  def handle_event("approve_version", %{"version_id" => version_id}, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        version = Procedures.get_version!(version_id)

        case Procedures.approve_version(version, scope.user.id) do
          {:ok, _version} ->
            reload_versions_and_procedure(socket, "Version approved and set as current")

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to approve: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to approve versions")}
    end
  end

  defp reload_versions_and_procedure(socket, message) do
    procedure = Procedures.get_procedure!(socket.assigns.selected_procedure.id)
    versions = Procedures.list_versions(procedure.id)

    # Load approval status for in_review versions
    versions_with_status =
      Enum.map(versions, fn version ->
        if version.status == :in_review do
          Map.put(version, :approval_status, Procedures.get_approval_status(version))
        else
          version
        end
      end)

    {:noreply,
     socket
     |> assign(:selected_procedure, procedure)
     |> assign(:versions, versions_with_status)
     |> put_flash(:info, message)}
  end

  def handle_event(
        "run_version",
        %{"version_id" => version_id, "procedure_id" => procedure_id},
        socket
      ) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :send_command, scope, mission) do
      :ok ->
        case Runtime.start_execution(mission.id, procedure_id,
               version_id: version_id,
               user_id: scope.user.id
             ) do
          {:ok, execution} ->
            {:noreply,
             socket
             |> put_flash(:info, "Procedure execution started")
             |> push_navigate(
               to: ~p"/missions/#{mission}/procedures/#{procedure_id}/executions/#{execution}"
             )}

          {:error, :mission_not_running} ->
            {:noreply, put_flash(socket, :error, "Mission is not currently active")}

          {:error, :at_concurrency_limit} ->
            {:noreply, put_flash(socket, :error, "Too many procedures running. Please wait.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to execute procedures")}
    end
  end

  def handle_event("delete", %{"id" => procedure_id}, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        procedure = Procedures.get_procedure(procedure_id)

        if procedure do
          case Procedures.delete_procedure(procedure) do
            {:ok, _} ->
              procedures =
                Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

              {:noreply,
               socket
               |> put_flash(:info, "Procedure deleted")
               |> assign(:procedures, procedures)}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to delete procedure")}
          end
        else
          {:noreply, put_flash(socket, :error, "Procedure not found")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete procedures")}
    end
  end

  def handle_event("export_procedure", %{"id" => procedure_id}, socket) do
    procedure = Procedures.get_procedure!(procedure_id)
    export_data = Procedures.export_procedure(procedure)
    json = Jason.encode!(export_data, pretty: true)
    filename = "#{procedure.name |> String.replace(~r/[^a-z0-9_-]/i, "_")}_export.json"

    {:noreply,
     push_event(socket, "download", %{
       filename: filename,
       content: json,
       content_type: "application/json"
     })}
  end

  def handle_event("show_import_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_import_modal, true)
     |> assign(:import_form, to_form(%{"json" => "", "name" => ""}))
     |> assign(:import_preview, nil)}
  end

  def handle_event("hide_import_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_import_modal, false)
     |> assign(:import_preview, nil)}
  end

  def handle_event("validate_import", %{"import" => import_params}, socket) do
    json_string = import_params["json"] || ""

    preview =
      case Jason.decode(json_string) do
        {:ok, data} ->
          # Validate basic structure
          if is_map(data["procedure"]) and is_binary(data["procedure"]["name"]) do
            data
          else
            nil
          end

        _ ->
          nil
      end

    {:noreply,
     socket
     |> assign(:import_form, to_form(import_params))
     |> assign(:import_preview, preview)}
  end

  def handle_event("import_procedure", %{"import" => import_params}, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope
    json_string = import_params["json"] || ""
    name = import_params["name"]
    name_opt = if name == "", do: [], else: [name: name]

    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        with {:ok, export_data} <- Jason.decode(json_string),
             {:ok, procedure} <-
               Procedures.import_procedure(
                 mission.organization_id,
                 mission.id,
                 export_data,
                 [user_id: scope.user.id] ++ name_opt
               ) do
          {:noreply,
           socket
           |> put_flash(:info, "Procedure '#{procedure.name}' imported successfully as draft")
           |> assign(:show_import_modal, false)
           |> push_navigate(to: ~p"/missions/#{mission}/procedures/#{procedure}")}
        else
          {:error, :invalid_export_format} ->
            {:noreply, put_flash(socket, :error, "Invalid export format")}

          {:error, :name_already_exists} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "A procedure with this name already exists. Please provide a different name."
             )}

          {:error, :missing_version_data} ->
            {:noreply, put_flash(socket, :error, "Export file contains no version data")}

          {:error, %Jason.DecodeError{}} ->
            {:noreply, put_flash(socket, :error, "Invalid JSON format")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to import procedure")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to import procedures")}
    end
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:execution_started, execution}, socket) do
    active_executions = [execution | socket.assigns.active_executions]
    execution_counts = update_count(socket.assigns.execution_counts, :running, 1)

    {:noreply,
     socket
     |> assign(:active_executions, active_executions)
     |> assign(:execution_counts, execution_counts)}
  end

  def handle_info({:execution_completed, execution}, socket) do
    active_executions =
      Enum.reject(socket.assigns.active_executions, &(&1.id == execution.id))

    execution_counts = update_count(socket.assigns.execution_counts, :running, -1)

    {:noreply,
     socket
     |> assign(:active_executions, active_executions)
     |> assign(:execution_counts, execution_counts)}
  end

  def handle_info({:execution_failed, execution}, socket) do
    active_executions =
      Enum.reject(socket.assigns.active_executions, &(&1.id == execution.id))

    execution_counts = update_count(socket.assigns.execution_counts, :running, -1)

    {:noreply,
     socket
     |> assign(:active_executions, active_executions)
     |> assign(:execution_counts, execution_counts)
     |> put_flash(:error, "Procedure #{execution.id} failed")}
  end

  def handle_info({:execution_paused, execution}, socket) do
    active_executions =
      Enum.map(socket.assigns.active_executions, fn ex ->
        if ex.id == execution.id, do: execution, else: ex
      end)

    {:noreply, assign(socket, :active_executions, active_executions)}
  end

  def handle_info({:execution_cancelled, execution}, socket) do
    active_executions =
      Enum.reject(socket.assigns.active_executions, &(&1.id == execution.id))

    {:noreply, assign(socket, :active_executions, active_executions)}
  end

  def handle_info({CadenceWeb.ProcedureLive.FormComponent, {:saved, _procedure}}, socket) do
    mission = socket.assigns.mission
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    {:noreply,
     socket
     |> assign(:procedures, procedures)
     |> push_patch(to: ~p"/missions/#{mission}/procedures")}
  end

  def handle_info(
        {CadenceWeb.ProcedureLive.ParameterFormComponent, {:submit_parameters, params}},
        socket
      ) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope
    procedure = socket.assigns.selected_procedure

    case Bodyguard.permit(Cadence.Missions.Policy, :send_command, scope, mission) do
      :ok ->
        case Runtime.start_execution(mission.id, procedure.id,
               parameters: params,
               user_id: scope.user.id
             ) do
          {:ok, execution} ->
            {:noreply,
             socket
             |> put_flash(:info, "Procedure execution started")
             |> push_navigate(
               to: ~p"/missions/#{mission}/procedures/#{procedure.id}/executions/#{execution}"
             )}

          {:error, :mission_not_running} ->
            {:noreply, put_flash(socket, :error, "Mission is not currently active")}

          {:error, :at_concurrency_limit} ->
            {:noreply, put_flash(socket, :error, "Too many procedures running. Please wait.")}

          {:error, {:validation_failed, errors}} ->
            error_msg = Enum.map_join(errors, ", ", fn {k, v} -> "#{k}: #{v}" end)
            {:noreply, put_flash(socket, :error, "Parameter validation failed: #{error_msg}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to execute procedures")}
    end
  end

  # Forward DAG editor step changes to the FormComponent
  def handle_info({CadenceWeb.ProcedureLive.DagEditorComponent, {:steps_changed, steps}}, socket) do
    # Use send_update to pass the updated steps to the FormComponent
    send_update(CadenceWeb.ProcedureLive.FormComponent,
      id: (socket.assigns.procedure && socket.assigns.procedure.id) || :new,
      dag_steps: steps
    )

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp update_count(counts, key, delta) do
    Map.update(counts, key, delta, &(&1 + delta))
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Procedures</h1>
          <p class="text-base-content/60 text-sm mt-1">
            Manage and execute operational procedures
          </p>
        </div>
        <div class="flex items-center gap-2">
          <div class="flex items-center gap-2 mr-4">
            <div
              :if={@execution_counts.running > 0}
              class="badge badge-success gap-1 animate-pulse"
            >
              <.icon name="hero-play" class="h-3 w-3" />
              {@execution_counts.running} running
            </div>
            <div :if={@execution_counts.paused > 0} class="badge badge-warning gap-1">
              <.icon name="hero-pause" class="h-3 w-3" />
              {@execution_counts.paused} paused
            </div>
          </div>
          <.button phx-click="show_import_modal" class="btn-ghost btn-sm">
            <.icon name="hero-arrow-down-tray" class="h-4 w-4 mr-1" /> Import
          </.button>
          <.link patch={~p"/missions/#{@mission}/procedures/new"}>
            <.button class="btn-primary btn-sm">
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> New Procedure
            </.button>
          </.link>
        </div>
      </div>
      
    <!-- Active Executions Banner -->
      <div
        :if={length(@active_executions) > 0}
        class="bg-success/10 border border-success/20 rounded-lg p-4"
      >
        <h3 class="font-medium text-success mb-2">Active Executions</h3>
        <div class="space-y-2">
          <div
            :for={execution <- @active_executions}
            class="flex items-center justify-between bg-base-100 rounded p-3"
          >
            <div class="flex items-center gap-3">
              <span class={[
                "w-2 h-2 rounded-full",
                execution.status == :running && "bg-success animate-pulse",
                execution.status == :paused && "bg-warning"
              ]}>
              </span>
              <div>
                <span class="font-medium">{execution.id |> String.slice(0, 8)}</span>
                <span class="text-sm text-base-content/60">
                  Step {execution.current_step_index || 0}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <.button
                :if={execution.status == :running}
                phx-click="pause_execution"
                phx-value-id={execution.id}
                class="btn-ghost btn-xs"
              >
                <.icon name="hero-pause" class="h-4 w-4" />
              </.button>
              <.button
                :if={execution.status == :paused}
                phx-click="resume_execution"
                phx-value-id={execution.id}
                class="btn-ghost btn-xs"
              >
                <.icon name="hero-play" class="h-4 w-4" />
              </.button>
              <.button
                phx-click="abort_execution"
                phx-value-id={execution.id}
                class="btn-ghost btn-xs text-error"
                data-confirm="Are you sure you want to abort this execution?"
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </.button>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Tag Filters -->
      <div :if={length(@available_tags) > 0} class="flex flex-wrap items-center gap-2">
        <span class="text-sm text-base-content/60">Filter by tags:</span>
        <button
          :for={tag <- @available_tags}
          type="button"
          phx-click="toggle_tag"
          phx-value-tag={tag}
          class={[
            "badge cursor-pointer transition-colors",
            tag in @selected_tags && "badge-primary",
            tag not in @selected_tags && "badge-outline hover:badge-primary"
          ]}
        >
          {tag}
        </button>
        <button
          :if={length(@selected_tags) > 0}
          type="button"
          phx-click="clear_tags"
          class="btn btn-ghost btn-xs"
        >
          Clear filters
        </button>
      </div>
      
    <!-- Procedures List -->
      <div class="card bg-base-200">
        <div class="card-body p-0">
          <%= if Enum.empty?(@procedures) and length(@selected_tags) > 0 do %>
            <div class="p-8 text-center">
              <.icon name="hero-funnel" class="h-12 w-12 mx-auto text-base-content/30" />
              <p class="mt-4 text-base-content/60">No procedures match the selected tags</p>
              <button type="button" phx-click="clear_tags" class="btn btn-ghost btn-sm mt-2">
                Clear filters
              </button>
            </div>
          <% else %>
            <%= if Enum.empty?(@procedures) do %>
              <div class="p-8 text-center">
                <.icon name="hero-document-text" class="h-12 w-12 mx-auto text-base-content/30" />
                <p class="mt-4 text-base-content/60">No procedures defined</p>
                <.link patch={~p"/missions/#{@mission}/procedures/new"} class="mt-4 inline-block">
                  <.button class="btn-primary btn-sm">
                    Create your first procedure
                  </.button>
                </.link>
              </div>
            <% else %>
              <table class="table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Tags</th>
                    <th>Type</th>
                    <th>Version</th>
                    <th>Status</th>
                    <th class="w-32"></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={procedure <- @procedures} class="hover">
                    <td>
                      <.link
                        patch={~p"/missions/#{@mission}/procedures/#{procedure.id}"}
                        class="font-medium hover:text-primary"
                      >
                        {procedure.name}
                      </.link>
                      <p :if={procedure.description} class="text-xs text-base-content/50 mt-1">
                        {String.slice(procedure.description, 0, 60)}
                      </p>
                    </td>
                    <td>
                      <div class="flex flex-wrap gap-1">
                        <span
                          :for={tag <- procedure.tags || []}
                          class="badge badge-sm badge-outline"
                        >
                          {tag}
                        </span>
                        <span
                          :if={length(procedure.tags || []) == 0}
                          class="text-base-content/40 text-xs"
                        >
                          -
                        </span>
                      </div>
                    </td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        procedure.type == :dag && "badge-primary",
                        procedure.type == :script && "badge-secondary"
                      ]}>
                        {procedure.type}
                      </span>
                    </td>
                    <td>
                      <%= if procedure.current_version_id do %>
                        <span class="text-sm">v{get_version_number(procedure)}</span>
                      <% else %>
                        <span class="text-sm text-base-content/40">-</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if procedure.current_version_id do %>
                        <span class="badge badge-sm badge-success">Ready</span>
                      <% else %>
                        <span class="badge badge-sm badge-warning">No version</span>
                      <% end %>
                    </td>
                    <td class="text-right">
                      <div class="flex items-center justify-end gap-1">
                        <.button
                          :if={procedure.current_version_id}
                          phx-click="execute"
                          phx-value-id={procedure.id}
                          class="btn-success btn-xs"
                        >
                          <.icon name="hero-play" class="h-3 w-3" />
                        </.button>
                        <.link patch={~p"/missions/#{@mission}/procedures/#{procedure.id}/edit"}>
                          <.button class="btn-ghost btn-xs">
                            <.icon name="hero-pencil" class="h-3 w-3" />
                          </.button>
                        </.link>
                        <.button
                          phx-click="delete"
                          phx-value-id={procedure.id}
                          class="btn-ghost btn-xs text-error"
                          data-confirm="Are you sure you want to delete this procedure?"
                        >
                          <.icon name="hero-trash" class="h-3 w-3" />
                        </.button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>

    <!-- New/Edit Procedure Modal -->
    <.modal
      :if={@live_action in [:new, :edit]}
      id="procedure-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/procedures")}
    >
      <.live_component
        module={CadenceWeb.ProcedureLive.FormComponent}
        id={@procedure.id || :new}
        title={if @live_action == :new, do: "New Procedure", else: "Edit Procedure"}
        action={@live_action}
        procedure={@procedure}
        mission={@mission}
        current_user={@current_scope.user}
        patch={~p"/missions/#{@mission}/procedures"}
      />
    </.modal>

    <!-- Procedure Detail Slide-over -->
    <.modal
      :if={@live_action in [:show, :execute] and @selected_procedure}
      id="procedure-detail-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/procedures")}
    >
      <div class="space-y-6">
        <div>
          <h3 class="text-lg font-bold">{@selected_procedure.name}</h3>
          <p :if={@selected_procedure.description} class="text-base-content/60 mt-1">
            {@selected_procedure.description}
          </p>
          <div :if={length(@selected_procedure.tags || []) > 0} class="flex flex-wrap gap-1 mt-2">
            <span
              :for={tag <- @selected_procedure.tags}
              class="badge badge-sm badge-outline"
            >
              {tag}
            </span>
          </div>
        </div>
        
    <!-- Version Info -->
        <div>
          <h4 class="font-medium mb-2">Versions</h4>
          <div class="space-y-3">
            <div
              :for={version <- @versions}
              class={[
                "p-3 rounded-lg",
                version.id == @selected_procedure.current_version_id &&
                  "bg-success/10 ring-1 ring-success/30",
                version.id != @selected_procedure.current_version_id && "bg-base-200"
              ]}
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="font-medium">v{version.version_number}</span>
                  <span class={[
                    "badge badge-sm",
                    version.status == :approved && "badge-success",
                    version.status == :draft && "badge-outline",
                    version.status == :in_review && "badge-warning",
                    version.status == :deprecated && "badge-ghost"
                  ]}>
                    <%= if version.status == :in_review do %>
                      awaiting approval
                    <% else %>
                      {version.status}
                    <% end %>
                  </span>
                  <%= if version.id == @selected_procedure.current_version_id do %>
                    <span class="badge badge-sm badge-info">current</span>
                  <% end %>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-base-content/50">
                    {Calendar.strftime(version.inserted_at, "%Y-%m-%d")}
                  </span>
                  <button
                    type="button"
                    phx-click="run_version"
                    phx-value-version_id={version.id}
                    phx-value-procedure_id={@selected_procedure.id}
                    class="btn btn-xs btn-ghost"
                    title="Run this version"
                  >
                    <.icon name="hero-play" class="h-3 w-3" />
                  </button>
                </div>
              </div>
              
    <!-- Draft: Submit for Review button -->
              <%= if version.status == :draft do %>
                <div class="mt-2 flex items-center gap-2">
                  <button
                    type="button"
                    phx-click="submit_for_review"
                    phx-value-version_id={version.id}
                    class="btn btn-xs btn-primary"
                    title="Submit for review"
                  >
                    <.icon name="hero-paper-airplane" class="h-3 w-3 mr-1" /> Submit for Review
                  </button>
                </div>
              <% end %>
              
    <!-- In Review: Approval status and actions -->
              <%= if version.status == :in_review do %>
                <div class="mt-3 pt-3 border-t border-base-300">
                  <!-- Approval Progress -->
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm text-base-content/70">Approval Progress</span>
                    <span class={[
                      "text-sm font-medium",
                      Map.get(version, :approval_status, %{})[:is_blocked] && "text-error",
                      not Map.get(version, :approval_status, %{})[:is_blocked] && "text-base-content"
                    ]}>
                      <%= if Map.get(version, :approval_status) do %>
                        {version.approval_status.approved} / {version.approval_status.required}
                        <%= if version.approval_status.is_blocked do %>
                          <span class="text-error ml-1">(blocked)</span>
                        <% end %>
                      <% end %>
                    </span>
                  </div>
                  
    <!-- Existing Approvals List -->
                  <%= if Map.get(version, :approval_status) && length(version.approval_status.approvals) > 0 do %>
                    <div class="space-y-1 mb-3">
                      <div
                        :for={approval <- version.approval_status.approvals}
                        class="flex items-center gap-2 text-sm"
                      >
                        <span class={[
                          "w-2 h-2 rounded-full",
                          approval.decision == :approved && "bg-success",
                          approval.decision == :rejected && "bg-error"
                        ]}>
                        </span>
                        <span class="font-medium">
                          {(approval.user && approval.user.email) || "Unknown"}
                        </span>
                        <span class={[
                          approval.decision == :approved && "text-success",
                          approval.decision == :rejected && "text-error"
                        ]}>
                          {approval.decision}
                        </span>
                        <%= if approval.comment do %>
                          <span class="text-base-content/50">- {approval.comment}</span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                  
    <!-- Action Buttons -->
                  <div class="flex flex-wrap items-center gap-2">
                    <button
                      type="button"
                      phx-click="add_approval"
                      phx-value-version_id={version.id}
                      phx-value-decision="approved"
                      class="btn btn-xs btn-success"
                      title="Approve this version"
                    >
                      <.icon name="hero-check" class="h-3 w-3 mr-1" /> Approve
                    </button>
                    <button
                      type="button"
                      phx-click="add_approval"
                      phx-value-version_id={version.id}
                      phx-value-decision="rejected"
                      class="btn btn-xs btn-error btn-outline"
                      title="Reject this version"
                    >
                      <.icon name="hero-x-mark" class="h-3 w-3 mr-1" /> Reject
                    </button>
                    <button
                      type="button"
                      phx-click="withdraw_submission"
                      phx-value-version_id={version.id}
                      class="btn btn-xs btn-ghost"
                      title="Withdraw submission"
                      data-confirm="Withdraw this submission? All approvals will be cleared."
                    >
                      Withdraw
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Execute Form -->
        <%= if @live_action == :execute do %>
          <div class="border-t border-base-300 pt-4">
            <h4 class="font-medium mb-4">Execute Procedure</h4>
            <.live_component
              module={CadenceWeb.ProcedureLive.ParameterFormComponent}
              id="parameter-form"
              parameters_schema={@parameters_schema}
              mission_id={@mission.id}
              values={%{}}
              on_cancel={JS.patch(~p"/missions/#{@mission}/procedures/#{@selected_procedure.id}")}
            />
          </div>
        <% else %>
          <!-- Action Buttons -->
          <div class="flex justify-end gap-2 border-t border-base-300 pt-4">
            <.button
              phx-click="export_procedure"
              phx-value-id={@selected_procedure.id}
              class="btn-ghost"
            >
              <.icon name="hero-arrow-up-tray" class="h-4 w-4 mr-1" /> Export
            </.button>
            <.link patch={~p"/missions/#{@mission}/procedures/#{@selected_procedure.id}/execute"}>
              <.button class="btn-success">
                <.icon name="hero-play" class="h-4 w-4 mr-1" /> Execute
              </.button>
            </.link>
          </div>
        <% end %>
        
    <!-- Recent Executions -->
        <div :if={@live_action == :show}>
          <h4 class="font-medium mb-2">Recent Executions</h4>
          <%= if Enum.empty?(@recent_executions) do %>
            <p class="text-sm text-base-content/50">No executions yet</p>
          <% else %>
            <div class="space-y-2">
              <.link
                :for={execution <- @recent_executions}
                navigate={
                  ~p"/missions/#{@mission}/procedures/#{@selected_procedure}/executions/#{execution}"
                }
                class="flex items-center justify-between p-2 bg-base-200 rounded hover:bg-base-300 transition-colors cursor-pointer"
              >
                <div class="flex items-center gap-2">
                  <span class={[
                    "w-2 h-2 rounded-full",
                    execution.status == :completed && "bg-success",
                    execution.status == :failed && "bg-error",
                    execution.status == :running && "bg-success animate-pulse",
                    execution.status == :paused && "bg-warning",
                    execution.status in [:pending, :cancelled] && "bg-base-content/30"
                  ]}>
                  </span>
                  <span class="font-mono text-sm">
                    {execution.id |> String.slice(0, 8)}
                  </span>
                  <span class={[
                    "text-xs px-1.5 py-0.5 rounded",
                    execution.status == :completed && "bg-success/20 text-success",
                    execution.status == :failed && "bg-error/20 text-error",
                    execution.status == :running && "bg-info/20 text-info",
                    execution.status == :paused && "bg-warning/20 text-warning",
                    execution.status in [:pending, :cancelled] &&
                      "bg-base-content/10 text-base-content/50"
                  ]}>
                    {Phoenix.Naming.humanize(execution.status)}
                  </span>
                </div>
                <div class="flex items-center gap-2 text-xs text-base-content/50">
                  <span>{Calendar.strftime(execution.inserted_at, "%Y-%m-%d %H:%M")}</span>
                  <.icon name="hero-chevron-right" class="h-4 w-4" />
                </div>
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </.modal>

    <!-- Import Modal -->
    <.modal
      :if={@show_import_modal}
      id="import-modal"
      show
      on_cancel={JS.push("hide_import_modal")}
    >
      <div class="space-y-4" id="import-container" phx-hook="Download">
        <h3 class="text-lg font-bold">Import Procedure</h3>
        <p class="text-sm text-base-content/60">
          Import a procedure from a JSON export file. The imported procedure will be created as a new draft that requires approval.
        </p>

        <.simple_form for={@import_form} phx-submit="import_procedure" phx-change="validate_import">
          <div class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text font-medium">Paste JSON export</span>
              </label>
              <textarea
                name="import[json]"
                class="textarea textarea-bordered w-full h-48 font-mono text-sm"
                placeholder='{"export_version": "1.0.0", ...}'
                phx-debounce="300"
              ><%= @import_form[:json].value %></textarea>
            </div>

            <!-- Import Preview -->
            <div :if={@import_preview} class="bg-base-200 rounded-lg p-4">
              <h4 class="font-medium mb-2">Preview</h4>
              <dl class="space-y-1 text-sm">
                <div class="flex gap-2">
                  <dt class="text-base-content/60">Name:</dt>
                  <dd class="font-medium">{@import_preview["procedure"]["name"]}</dd>
                </div>
                <div :if={@import_preview["procedure"]["description"]} class="flex gap-2">
                  <dt class="text-base-content/60">Description:</dt>
                  <dd>{@import_preview["procedure"]["description"]}</dd>
                </div>
                <div class="flex gap-2">
                  <dt class="text-base-content/60">Type:</dt>
                  <dd><span class="badge badge-sm">{@import_preview["procedure"]["type"]}</span></dd>
                </div>
                <div :if={length(@import_preview["procedure"]["tags"] || []) > 0} class="flex gap-2">
                  <dt class="text-base-content/60">Tags:</dt>
                  <dd>
                    <span :for={tag <- @import_preview["procedure"]["tags"]} class="badge badge-sm badge-outline mr-1">
                      {tag}
                    </span>
                  </dd>
                </div>
              </dl>
            </div>

            <div>
              <label class="label">
                <span class="label-text">Name override (optional)</span>
              </label>
              <input
                type="text"
                name="import[name]"
                class="input input-bordered w-full"
                placeholder="Leave empty to use original name"
                value={@import_form[:name].value}
              />
              <p class="text-xs text-base-content/60 mt-1">
                Use this if a procedure with the same name already exists
              </p>
            </div>
          </div>

          <:actions>
            <.button type="button" class="btn-ghost" phx-click="hide_import_modal">
              Cancel
            </.button>
            <.button type="submit" class="btn-primary" disabled={is_nil(@import_preview)}>
              <.icon name="hero-arrow-down-tray" class="h-4 w-4 mr-1" /> Import
            </.button>
          </:actions>
        </.simple_form>
      </div>
    </.modal>
    """
  end

  defp get_version_number(procedure) do
    if procedure.current_version_id do
      case Procedures.get_version(procedure.current_version_id) do
        nil -> "?"
        version -> version.version_number
      end
    else
      "-"
    end
  end
end
