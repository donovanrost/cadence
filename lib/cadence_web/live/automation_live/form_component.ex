defmodule CadenceWeb.AutomationLive.FormComponent do
  @moduledoc """
  Form component for creating and editing automations.
  """
  use CadenceWeb, :live_component

  alias Cadence.Automations

  @trigger_types [
    {"Alarm Fired", "alarm_fired"},
    {"Alarm Cleared", "alarm_cleared"},
    {"Alarm Acknowledged", "alarm_acknowledged"},
    {"Telemetry Limit", "telemetry_limit"},
    {"Procedure Completed", "procedure_completed"},
    {"Procedure Failed", "procedure_failed"}
  ]

  @action_types [
    {"Execute Procedure", "execute_procedure"},
    {"Acknowledge Alarm", "acknowledge_alarm"},
    {"Shelve Alarm", "shelve_alarm"},
    {"Send Notification", "send_notification"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Configure when and how this automation triggers.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="automation-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />

        <.input field={@form[:description]} type="textarea" label="Description" rows={2} />

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:trigger_type]}
            type="select"
            label="Trigger Type"
            options={@trigger_types}
          />

          <.input
            field={@form[:action_type]}
            type="select"
            label="Action Type"
            options={@action_types}
          />
        </div>
        
    <!-- Trigger Conditions -->
        <div class="border rounded-lg p-4 bg-gray-50">
          <h4 class="text-sm font-medium text-gray-900 mb-3">Trigger Conditions</h4>
          <p class="text-xs text-gray-500 mb-3">
            Leave blank to match all events of this type.
          </p>

          <div
            :if={@form[:trigger_type].value in ["alarm_fired", "alarm_cleared", "alarm_acknowledged"]}
            class="space-y-3"
          >
            <.input
              field={@form[:severity_filter]}
              type="text"
              label="Severity Filter"
              placeholder="e.g., critical,warning"
            />
            <.input
              field={@form[:item_pattern]}
              type="text"
              label="Item Pattern"
              placeholder="e.g., TEMP_.*"
            />
          </div>

          <div :if={@form[:trigger_type].value == "telemetry_limit"} class="space-y-3">
            <.input
              field={@form[:state_filter]}
              type="text"
              label="State Filter"
              placeholder="e.g., red,yellow"
            />
            <.input
              field={@form[:item_pattern]}
              type="text"
              label="Item Pattern"
              placeholder="e.g., TEMP_.*"
            />
          </div>

          <div
            :if={@form[:trigger_type].value in ["procedure_completed", "procedure_failed"]}
            class="space-y-3"
          >
            <.input
              field={@form[:procedure_filter]}
              type="text"
              label="Procedure Name Pattern"
              placeholder="e.g., SAFE_MODE_.*"
            />
          </div>
        </div>
        
    <!-- Action Configuration -->
        <div class="border rounded-lg p-4 bg-gray-50">
          <h4 class="text-sm font-medium text-gray-900 mb-3">Action Configuration</h4>

          <div :if={@form[:action_type].value == "execute_procedure"} class="space-y-3">
            <.input
              field={@form[:procedure_id]}
              type="select"
              label="Procedure to Execute"
              options={@procedure_options}
              prompt="Select a procedure..."
            />
            <.input
              field={@form[:inject_trigger_data]}
              type="checkbox"
              label="Pass trigger event data to procedure"
            />
          </div>

          <div :if={@form[:action_type].value == "acknowledge_alarm"} class="space-y-3">
            <.input
              field={@form[:acknowledge_note]}
              type="text"
              label="Acknowledgment Note"
              placeholder="Auto-acknowledged by automation"
            />
          </div>

          <div :if={@form[:action_type].value == "shelve_alarm"} class="space-y-3">
            <.input
              field={@form[:shelve_duration]}
              type="number"
              label="Shelve Duration (minutes)"
              min="1"
              value="60"
            />
            <.input
              field={@form[:shelve_reason]}
              type="text"
              label="Shelve Reason"
              placeholder="Auto-shelved by automation"
            />
          </div>

          <div :if={@form[:action_type].value == "send_notification"} class="space-y-3">
            <.input
              field={@form[:notification_channel]}
              type="text"
              label="Channel"
              placeholder="default"
            />
            <.input
              field={@form[:notification_template]}
              type="textarea"
              label="Message Template"
              rows={2}
              placeholder="Automation triggered: {{trigger_type}}"
            />
          </div>
        </div>
        
    <!-- Rate Limiting -->
        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:cooldown_seconds]}
            type="number"
            label="Cooldown (seconds)"
            min="0"
          />
          <.input
            field={@form[:max_executions_per_hour]}
            type="number"
            label="Max Executions/Hour"
            min="1"
          />
        </div>

        <:actions>
          <.button phx-disable-with="Saving..." class="btn-primary">Save Automation</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{automation: automation} = assigns, socket) do
    changeset = Automations.change_automation(automation)

    # Build procedure options
    procedure_options =
      Enum.map(assigns.procedures, fn p ->
        {p.name, p.id}
      end)

    # Extract conditions and config for form fields
    conditions = automation.trigger_conditions || %{}
    config = automation.action_config || %{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:trigger_types, @trigger_types)
     |> assign(:action_types, @action_types)
     |> assign(:procedure_options, procedure_options)
     |> assign(:severity_filter, format_list(conditions["severity_in"]))
     |> assign(:state_filter, format_list(conditions["state_in"]))
     |> assign(:item_pattern, conditions["item_pattern"])
     |> assign(:procedure_filter, conditions["procedure_name_pattern"])
     |> assign(:procedure_id, config["procedure_id"])
     |> assign(:inject_trigger_data, config["inject_trigger_data"] || false)
     |> assign(:acknowledge_note, config["note"])
     |> assign(:shelve_duration, config["duration_minutes"] || 60)
     |> assign(:shelve_reason, config["reason"])
     |> assign(:notification_channel, config["channel"])
     |> assign(:notification_template, config["message_template"])
     |> assign_form(changeset)}
  end

  defp format_list(nil), do: ""
  defp format_list(list) when is_list(list), do: Enum.join(list, ",")
  defp format_list(other), do: to_string(other)

  @impl true
  def handle_event("validate", %{"automation" => automation_params}, socket) do
    changeset =
      socket.assigns.automation
      |> Automations.change_automation(automation_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"automation" => automation_params} = params, socket) do
    # Build trigger_conditions from form inputs
    trigger_conditions = build_trigger_conditions(automation_params["trigger_type"], params)

    # Build action_config from form inputs
    action_config = build_action_config(automation_params["action_type"], params)

    # Merge into automation params
    full_params =
      automation_params
      |> Map.put("trigger_conditions", trigger_conditions)
      |> Map.put("action_config", action_config)
      |> Map.put("organization_id", socket.assigns.mission.organization_id)
      |> Map.put("mission_id", socket.assigns.mission.id)

    save_automation(socket, socket.assigns.action, full_params)
  end

  defp build_trigger_conditions(trigger_type, params) do
    conditions = %{}

    conditions =
      case trigger_type do
        type when type in ["alarm_fired", "alarm_cleared", "alarm_acknowledged"] ->
          conditions
          |> maybe_add_list("severity_in", params["automation"]["severity_filter"])
          |> maybe_add_string("item_pattern", params["automation"]["item_pattern"])

        "telemetry_limit" ->
          conditions
          |> maybe_add_list("state_in", params["automation"]["state_filter"])
          |> maybe_add_string("item_pattern", params["automation"]["item_pattern"])

        type when type in ["procedure_completed", "procedure_failed"] ->
          conditions
          |> maybe_add_string("procedure_name_pattern", params["automation"]["procedure_filter"])

        _ ->
          conditions
      end

    conditions
  end

  defp build_action_config(action_type, params) do
    case action_type do
      "execute_procedure" ->
        %{
          "procedure_id" => params["automation"]["procedure_id"],
          "inject_trigger_data" => params["automation"]["inject_trigger_data"] == "true"
        }
        |> Map.reject(fn {_k, v} -> v == "" or is_nil(v) end)

      "acknowledge_alarm" ->
        %{"note" => params["automation"]["acknowledge_note"]}
        |> Map.reject(fn {_k, v} -> v == "" or is_nil(v) end)

      "shelve_alarm" ->
        duration = parse_integer(params["automation"]["shelve_duration"], 60)

        %{
          "duration_minutes" => duration,
          "reason" => params["automation"]["shelve_reason"]
        }
        |> Map.reject(fn {_k, v} -> v == "" or is_nil(v) end)

      "send_notification" ->
        %{
          "channel" => params["automation"]["notification_channel"],
          "message_template" => params["automation"]["notification_template"]
        }
        |> Map.reject(fn {_k, v} -> v == "" or is_nil(v) end)

      _ ->
        %{}
    end
  end

  defp maybe_add_list(map, _key, nil), do: map
  defp maybe_add_list(map, _key, ""), do: map

  defp maybe_add_list(map, key, value) do
    list =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if list == [], do: map, else: Map.put(map, key, list)
  end

  defp maybe_add_string(map, _key, nil), do: map
  defp maybe_add_string(map, _key, ""), do: map
  defp maybe_add_string(map, key, value), do: Map.put(map, key, String.trim(value))

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(value, _default) when is_integer(value), do: value

  defp save_automation(socket, :edit, automation_params) do
    case Automations.update_automation(socket.assigns.automation, automation_params) do
      {:ok, automation} ->
        notify_parent({:saved, automation})

        {:noreply,
         socket
         |> put_flash(:info, "Automation updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_automation(socket, :new, automation_params) do
    case Automations.create_automation(automation_params) do
      {:ok, automation} ->
        notify_parent({:saved, automation})

        {:noreply,
         socket
         |> put_flash(:info, "Automation created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
