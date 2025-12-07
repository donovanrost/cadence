defmodule CadenceWeb.ScheduleLive.FormComponent do
  @moduledoc """
  Form component for creating and editing schedules.
  """
  use CadenceWeb, :live_component

  alias Cadence.Schedules

  @schedule_types [
    {"Recurring (Cron)", :cron},
    {"One-time", :once}
  ]

  @common_cron_presets [
    {"Every minute", "* * * * *"},
    {"Every 5 minutes", "*/5 * * * *"},
    {"Every 15 minutes", "*/15 * * * *"},
    {"Every hour", "0 * * * *"},
    {"Every day at midnight", "0 0 * * *"},
    {"Every day at 8am", "0 8 * * *"},
    {"Every Monday at 9am", "0 9 * * 1"},
    {"Every month on the 1st", "0 0 1 * *"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Configure when this procedure should be automatically executed.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="schedule-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />

        <.input field={@form[:description]} type="textarea" label="Description" rows={2} />

        <.input
          field={@form[:procedure_id]}
          type="select"
          label="Procedure"
          options={@procedure_options}
          prompt="Select a procedure..."
          required
        />

        <.input
          field={@form[:schedule_type]}
          type="select"
          label="Schedule Type"
          options={@schedule_types}
        />

        <!-- Cron Configuration -->
        <div :if={to_string(@form[:schedule_type].value) == "cron"} class="space-y-4">
          <div class="border rounded-lg p-4 bg-gray-50">
            <h4 class="text-sm font-medium text-gray-900 mb-3">Cron Expression</h4>

            <div class="mb-3">
              <label class="block text-sm font-medium text-gray-700 mb-1">Quick Presets</label>
              <select
                phx-change="select_preset"
                phx-target={@myself}
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              >
                <option value="">Choose a preset...</option>
                <%= for {label, cron} <- @cron_presets do %>
                  <option value={cron}>{label}</option>
                <% end %>
              </select>
            </div>

            <.input
              field={@form[:cron_expression]}
              type="text"
              label="Cron Expression"
              placeholder="* * * * *"
              required
            />

            <p class="mt-2 text-xs text-gray-500">
              Format: minute hour day month weekday (e.g., "0 8 * * *" for daily at 8am)
            </p>

            <%= if @cron_description do %>
              <div class="mt-2 p-2 bg-blue-50 rounded text-sm text-blue-700">
                {@cron_description}
              </div>
            <% end %>
          </div>

          <.input
            field={@form[:timezone]}
            type="select"
            label="Timezone"
            options={@timezone_options}
          />
        </div>

        <!-- One-time Configuration -->
        <div :if={to_string(@form[:schedule_type].value) == "once"} class="space-y-4">
          <div class="border rounded-lg p-4 bg-gray-50">
            <h4 class="text-sm font-medium text-gray-900 mb-3">Scheduled Time</h4>

            <.input
              field={@form[:scheduled_at]}
              type="datetime-local"
              label="Run At"
              required
            />

            <p class="mt-2 text-xs text-gray-500">
              The procedure will run once at this time (in UTC).
            </p>
          </div>
        </div>

        <!-- Parameters (Optional) -->
        <div class="border rounded-lg p-4 bg-gray-50">
          <h4 class="text-sm font-medium text-gray-900 mb-3">Parameters (Optional)</h4>
          <.input
            field={@form[:parameters_json]}
            type="textarea"
            label="Parameters JSON"
            rows={3}
            placeholder="{}"
          />
          <p class="mt-2 text-xs text-gray-500">
            JSON object with parameters to pass to the procedure.
          </p>
          <%= if @parameters_error do %>
            <p class="mt-2 text-sm text-red-600">{@parameters_error}</p>
          <% end %>
        </div>

        <:actions>
          <.button phx-disable-with="Saving..." class="btn-primary">Save Schedule</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{schedule: schedule} = assigns, socket) do
    changeset = Schedules.change_schedule(schedule)

    # Build procedure options
    procedure_options =
      Enum.map(assigns.procedures, fn p ->
        {p.name, p.id}
      end)

    # Format parameters as JSON for editing
    parameters_json =
      case schedule.parameters do
        nil -> "{}"
        params when map_size(params) == 0 -> "{}"
        params -> Jason.encode!(params, pretty: true)
      end

    # Common timezones
    timezone_options = [
      {"UTC", "UTC"},
      {"US/Eastern", "US/Eastern"},
      {"US/Central", "US/Central"},
      {"US/Mountain", "US/Mountain"},
      {"US/Pacific", "US/Pacific"},
      {"Europe/London", "Europe/London"},
      {"Europe/Paris", "Europe/Paris"},
      {"Asia/Tokyo", "Asia/Tokyo"}
    ]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:schedule_types, @schedule_types)
     |> assign(:cron_presets, @common_cron_presets)
     |> assign(:procedure_options, procedure_options)
     |> assign(:timezone_options, timezone_options)
     |> assign(:parameters_json, parameters_json)
     |> assign(:parameters_error, nil)
     |> assign(:cron_description, describe_cron(schedule.cron_expression))
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"schedule" => schedule_params}, socket) do
    changeset =
      socket.assigns.schedule
      |> Schedules.change_schedule(schedule_params)
      |> Map.put(:action, :validate)

    cron_description = describe_cron(schedule_params["cron_expression"])

    {:noreply,
     socket
     |> assign(:cron_description, cron_description)
     |> assign_form(changeset)}
  end

  def handle_event("select_preset", %{"value" => cron}, socket) do
    # Update the form with the selected cron expression
    changeset =
      socket.assigns.schedule
      |> Schedules.change_schedule(%{cron_expression: cron})

    {:noreply,
     socket
     |> assign(:cron_description, describe_cron(cron))
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"schedule" => schedule_params} = params, socket) do
    # Parse parameters JSON
    parameters_json = params["schedule"]["parameters_json"] || "{}"

    case Jason.decode(parameters_json) do
      {:ok, parameters} ->
        full_params =
          schedule_params
          |> Map.put("parameters", parameters)
          |> Map.put("organization_id", socket.assigns.mission.organization_id)
          |> Map.put("mission_id", socket.assigns.mission.id)

        save_schedule(socket, socket.assigns.action, full_params)

      {:error, _} ->
        {:noreply, assign(socket, :parameters_error, "Invalid JSON format")}
    end
  end

  defp save_schedule(socket, :edit, schedule_params) do
    case Schedules.update_schedule(socket.assigns.schedule, schedule_params) do
      {:ok, schedule} ->
        notify_parent({:saved, schedule})

        {:noreply,
         socket
         |> put_flash(:info, "Schedule updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_schedule(socket, :new, schedule_params) do
    case Schedules.create_schedule(schedule_params) do
      {:ok, schedule} ->
        notify_parent({:saved, schedule})

        {:noreply,
         socket
         |> put_flash(:info, "Schedule created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  # Simple cron description helper
  defp describe_cron(nil), do: nil
  defp describe_cron(""), do: nil

  defp describe_cron(cron) do
    case String.split(cron, " ") do
      ["*", "*", "*", "*", "*"] ->
        "Runs every minute"

      ["*/5", "*", "*", "*", "*"] ->
        "Runs every 5 minutes"

      ["*/15", "*", "*", "*", "*"] ->
        "Runs every 15 minutes"

      ["0", "*", "*", "*", "*"] ->
        "Runs at the start of every hour"

      ["0", "0", "*", "*", "*"] ->
        "Runs daily at midnight"

      ["0", hour, "*", "*", "*"] ->
        "Runs daily at #{hour}:00"

      ["0", hour, "*", "*", day] when day != "*" ->
        day_name = weekday_name(day)
        "Runs every #{day_name} at #{hour}:00"

      ["0", "0", "1", "*", "*"] ->
        "Runs on the 1st of every month"

      _ ->
        "Custom schedule: #{cron}"
    end
  end

  defp weekday_name("0"), do: "Sunday"
  defp weekday_name("1"), do: "Monday"
  defp weekday_name("2"), do: "Tuesday"
  defp weekday_name("3"), do: "Wednesday"
  defp weekday_name("4"), do: "Thursday"
  defp weekday_name("5"), do: "Friday"
  defp weekday_name("6"), do: "Saturday"
  defp weekday_name("7"), do: "Sunday"
  defp weekday_name(other), do: "day #{other}"
end
