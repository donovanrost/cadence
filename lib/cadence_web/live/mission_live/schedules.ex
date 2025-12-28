defmodule CadenceWeb.MissionLive.Schedules do
  @moduledoc """
  LiveView for managing scheduled procedure executions within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Procedures, Schedules}
  # Use Ecto schema for form handling (changesets), domain entity for operations
  alias Cadence.Schedules.Schedule, as: ScheduleSchema

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
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

  defp apply_action(socket, :index, _params) do
    mission = socket.assigns.mission
    schedules = Schedules.list_schedules(mission.organization_id, mission_id: mission.id)
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    socket
    |> assign(:page_title, "Schedules")
    |> assign(:schedules, schedules)
    |> assign(:procedures, procedures)
    |> assign(:schedule, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    schedules = Schedules.list_schedules(mission.organization_id, mission_id: mission.id)
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    socket
    |> assign(:page_title, "New Schedule")
    |> assign(:schedules, schedules)
    |> assign(:procedures, procedures)
    |> assign(:schedule, %ScheduleSchema{
      enabled: true,
      schedule_type: :cron,
      timezone: "UTC"
    })
  end

  defp apply_action(socket, :edit, %{"schedule_id" => schedule_id}) do
    mission = socket.assigns.mission
    schedule_entity = Schedules.get_schedule!(schedule_id, mission.organization_id)
    schedules = Schedules.list_schedules(mission.organization_id, mission_id: mission.id)
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    if schedule_entity.mission_id == mission.id do
      # Convert domain entity to Ecto schema for form changeset handling
      schedule_schema = entity_to_schema(schedule_entity)

      socket
      |> assign(:page_title, "Edit Schedule")
      |> assign(:schedules, schedules)
      |> assign(:procedures, procedures)
      |> assign(:schedule, schedule_schema)
    else
      socket
      |> put_flash(:error, "Schedule not found in this mission")
      |> push_patch(to: ~p"/missions/#{mission}/schedules")
    end
  end

  @impl true
  def handle_info({CadenceWeb.ScheduleLive.FormComponent, {:saved, _schedule}}, socket) do
    schedules =
      Schedules.list_schedules(socket.assigns.mission.organization_id,
        mission_id: socket.assigns.mission.id
      )

    {:noreply, assign(socket, :schedules, schedules)}
  end

  @impl true
  def handle_event("toggle", %{"id" => schedule_id}, socket) do
    mission = socket.assigns.mission
    schedule = Schedules.get_schedule!(schedule_id, mission.organization_id)
    scope = socket.assigns.current_scope

    if schedule.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          result =
            if schedule.enabled do
              Schedules.disable_schedule(schedule)
            else
              Schedules.enable_schedule(schedule)
            end

          case result do
            {:ok, _} ->
              schedules =
                Schedules.list_schedules(mission.organization_id, mission_id: mission.id)

              action = if schedule.enabled, do: "disabled", else: "enabled"

              {:noreply,
               socket
               |> put_flash(:info, "Schedule #{action}")
               |> assign(:schedules, schedules)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update schedule")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to manage schedules")}
      end
    else
      {:noreply, put_flash(socket, :error, "Schedule not found in this mission")}
    end
  end

  @impl true
  def handle_event("run_now", %{"id" => schedule_id}, socket) do
    mission = socket.assigns.mission
    schedule = Schedules.get_schedule!(schedule_id, mission.organization_id)
    scope = socket.assigns.current_scope

    if schedule.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Schedules.enqueue_schedule(schedule) do
            {:ok, _job} ->
              {:noreply,
               socket
               |> put_flash(:info, "Schedule queued for immediate execution")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to enqueue: #{inspect(reason)}")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to run schedules")}
      end
    else
      {:noreply, put_flash(socket, :error, "Schedule not found in this mission")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => schedule_id}, socket) do
    mission = socket.assigns.mission
    schedule = Schedules.get_schedule!(schedule_id, mission.organization_id)
    scope = socket.assigns.current_scope

    if schedule.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Schedules.delete_schedule(schedule) do
            {:ok, _} ->
              schedules =
                Schedules.list_schedules(mission.organization_id, mission_id: mission.id)

              {:noreply,
               socket
               |> put_flash(:info, "Schedule deleted")
               |> assign(:schedules, schedules)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to delete schedule")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete schedules")}
      end
    else
      {:noreply, put_flash(socket, :error, "Schedule not found in this mission")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Schedules
      <:subtitle>
        Scheduled procedure executions using cron expressions or one-time triggers
      </:subtitle>
      <:actions>
        <.link patch={~p"/missions/#{@mission}/schedules/new"}>
          <.button>New Schedule</.button>
        </.link>
      </:actions>
    </.header>

    <.table id="schedules" rows={@schedules}>
      <:col :let={schedule} label="Name">
        <div>
          <div class="font-medium">{schedule.name}</div>
          <div class="text-xs text-gray-500">{schedule.procedure && schedule.procedure.name}</div>
        </div>
      </:col>
      <:col :let={schedule} label="Schedule">
        <%= if schedule.schedule_type == :cron do %>
          <code class="text-sm bg-gray-100 px-2 py-1 rounded">{schedule.cron_expression}</code>
        <% else %>
          <span class="text-sm">
            {Calendar.strftime(schedule.scheduled_at, "%Y-%m-%d %H:%M UTC")}
          </span>
        <% end %>
      </:col>
      <:col :let={schedule} label="Type">
        <span class={[
          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
          schedule.schedule_type == :cron && "bg-blue-50 text-blue-700 ring-blue-600/20",
          schedule.schedule_type == :once && "bg-purple-50 text-purple-700 ring-purple-600/20"
        ]}>
          {if schedule.schedule_type == :cron, do: "Recurring", else: "One-time"}
        </span>
      </:col>
      <:col :let={schedule} label="Last Run">
        <%= if schedule.last_run_at do %>
          <span class="text-sm text-gray-600">
            {Calendar.strftime(schedule.last_run_at, "%Y-%m-%d %H:%M")}
          </span>
        <% else %>
          <span class="text-sm text-gray-400">Never</span>
        <% end %>
      </:col>
      <:col :let={schedule} label="Runs">
        <span class="text-gray-500">{schedule.run_count}</span>
      </:col>
      <:col :let={schedule} label="Status">
        <.status_badge status={schedule.enabled} true_label="Enabled" false_label="Disabled" />
      </:col>
      <:action :let={schedule}>
        <.link phx-click={JS.push("run_now", value: %{id: schedule.id})}>Run Now</.link>
        <.link phx-click={JS.push("toggle", value: %{id: schedule.id})}>
          {if schedule.enabled, do: "Disable", else: "Enable"}
        </.link>
        <.link patch={~p"/missions/#{@mission}/schedules/#{schedule}/edit"}>Edit</.link>
        <.link
          phx-click={JS.push("delete", value: %{id: schedule.id})}
          data-confirm="Are you sure you want to delete this schedule?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <%= if Enum.empty?(@schedules) do %>
      <div class="text-center py-12 border border-dashed border-gray-300 rounded-lg mt-4">
        <.icon name="hero-clock" class="mx-auto h-12 w-12 text-gray-400" />
        <h3 class="mt-2 text-sm font-semibold text-gray-900">No schedules</h3>
        <p class="mt-1 text-sm text-gray-500">
          Create schedules to automatically run procedures at specific times.
        </p>
        <div class="mt-6">
          <.link patch={~p"/missions/#{@mission}/schedules/new"}>
            <.button>
              <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Schedule
            </.button>
          </.link>
        </div>
      </div>
    <% end %>

    <!-- Schedule Modal -->
    <.modal
      :if={@live_action in [:new, :edit]}
      id="schedule-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/schedules")}
    >
      <.live_component
        module={CadenceWeb.ScheduleLive.FormComponent}
        id={@schedule.id || :new}
        title={@page_title}
        action={if @live_action == :new, do: :new, else: :edit}
        schedule={@schedule}
        mission={@mission}
        procedures={@procedures}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/schedules"}
      />
    </.modal>
    """
  end

  # Converts a domain entity to an Ecto schema for form changeset handling
  defp entity_to_schema(entity) do
    %ScheduleSchema{
      id: entity.id,
      name: entity.name,
      description: entity.description,
      enabled: entity.enabled,
      schedule_type: entity.schedule_type,
      cron_expression: entity.cron_expression,
      scheduled_at: entity.scheduled_at,
      timezone: entity.timezone,
      parameters: entity.parameters,
      last_run_at: entity.last_run_at,
      next_run_at: entity.next_run_at,
      run_count: entity.run_count,
      procedure_id: entity.procedure_id,
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      target_id: entity.target_id,
      inserted_at: entity.inserted_at,
      updated_at: entity.updated_at
    }
  end
end
