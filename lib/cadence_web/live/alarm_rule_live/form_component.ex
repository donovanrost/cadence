defmodule CadenceWeb.AlarmRuleLive.FormComponent do
  @moduledoc """
  Form component for creating and editing alarm rules.
  """

  use CadenceWeb, :live_component

  alias Cadence.Alarms
  alias Cadence.Alarms.AlarmRule

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Alarm rules define when alarms are generated from telemetry events.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="alarm-rule-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="e.g., Battery Critical Alert"
        />

        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          placeholder="Optional description of what this rule monitors"
        />

        <.input
          field={@form[:event_type]}
          type="select"
          label="Event Type"
          options={[{"Telemetry Limit Violation", "telemetry_limit"}]}
        />

        <.input
          field={@form[:severity]}
          type="select"
          label="Alarm Severity"
          options={[
            {"Info", "info"},
            {"Warning", "warning"},
            {"Critical", "critical"}
          ]}
        />

        <div class="space-y-2">
          <label class="block text-sm font-semibold leading-6 text-zinc-800">
            Conditions
          </label>
          <p class="text-sm text-zinc-600">
            Define which events trigger this rule. All conditions must match.
          </p>

          <div class="bg-zinc-50 rounded-lg p-4 space-y-4">
            <div>
              <label class="block text-sm font-medium text-zinc-700 mb-1">Limit States</label>
              <p class="text-xs text-zinc-500 mb-2">Which limit states should trigger this rule?</p>
              <div class="flex flex-wrap gap-3">
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    name="conditions[limit_state][]"
                    value="red"
                    checked={@conditions_limit_states["red"]}
                    class="checkbox checkbox-sm checkbox-error"
                  />
                  <span class="text-sm">Red (Critical)</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    name="conditions[limit_state][]"
                    value="yellow"
                    checked={@conditions_limit_states["yellow"]}
                    class="checkbox checkbox-sm checkbox-warning"
                  />
                  <span class="text-sm">Yellow (Warning)</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    name="conditions[limit_state][]"
                    value="blue"
                    checked={@conditions_limit_states["blue"]}
                    class="checkbox checkbox-sm checkbox-info"
                  />
                  <span class="text-sm">Blue (Stale)</span>
                </label>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-zinc-700 mb-1">
                Item Filter (Optional)
              </label>
              <p class="text-xs text-zinc-500 mb-2">
                Leave empty to match all items, or enter a pattern like
                <code class="bg-zinc-200 px-1 rounded">POWER\..*</code>
              </p>
              <input
                type="text"
                name="conditions[item_name_pattern]"
                value={@conditions_item_pattern}
                placeholder="e.g., POWER\\.battery_.*"
                class="input input-bordered w-full"
              />
            </div>
          </div>
        </div>

        <.input
          field={@form[:message_template]}
          type="textarea"
          label="Message Template"
          placeholder="{{item_name}} is {{limit_state}} (value: {{value}})"
          rows="2"
        />
        <p class="text-xs text-zinc-500 -mt-4">
          Available variables: <code>{"{{item_name}}"}</code>, <code>{"{{value}}"}</code>, <code>{"{{limit_state}}"}</code>, <code>{"{{previous_state}}"}</code>,
          <code>{"{{target_id}}"}</code>
        </p>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <.input
              field={@form[:auto_shelve_duration_minutes]}
              type="number"
              label="Auto-Shelve Duration (minutes)"
              placeholder="Leave empty to disable"
            />
            <p class="text-xs text-zinc-500 mt-1">
              Automatically shelve alarms for this duration when triggered
            </p>
          </div>

          <div>
            <.input
              field={@form[:cooldown_seconds]}
              type="number"
              label="Cooldown (seconds)"
              placeholder="Leave empty for no cooldown"
            />
            <p class="text-xs text-zinc-500 mt-1">
              Minimum time between re-triggering after clear
            </p>
          </div>
        </div>

        <.input
          field={@form[:enabled]}
          type="checkbox"
          label="Enabled"
        />
        <p class="text-sm text-gray-600 -mt-4 ml-6">
          Disabled rules will not generate alarms.
        </p>

        <:actions>
          <.button phx-disable-with="Saving..." type="submit">
            {if @action == :new, do: "Create Rule", else: "Save Changes"}
          </.button>
        </:actions>
      </.simple_form>

      <div :if={@action == :edit} class="mt-8 pt-6 border-t border-zinc-200">
        <.button
          phx-click="delete"
          phx-target={@myself}
          data-confirm="Are you sure you want to delete this alarm rule?"
          class="bg-red-600 hover:bg-red-700"
        >
          Delete Rule
        </.button>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{alarm_rule: alarm_rule} = assigns, socket) do
    # Extract conditions for form state
    conditions = alarm_rule.conditions || %{}
    limit_states = Map.get(conditions, "limit_state", [])

    conditions_limit_states = %{
      "red" => "red" in limit_states,
      "yellow" => "yellow" in limit_states,
      "blue" => "blue" in limit_states
    }

    conditions_item_pattern = Map.get(conditions, "item_name_pattern", "")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:conditions_limit_states, conditions_limit_states)
     |> assign(:conditions_item_pattern, conditions_item_pattern)
     |> assign_form(AlarmRule.changeset(alarm_rule, %{}))}
  end

  @impl true
  def handle_event("validate", params, socket) do
    alarm_rule_params = Map.get(params, "alarm_rule", %{})

    # Parse conditions from form
    conditions_params = Map.get(params, "conditions", %{})
    conditions = build_conditions(conditions_params)

    # Update conditions state for checkboxes
    limit_states = Map.get(conditions_params, "limit_state", [])

    conditions_limit_states = %{
      "red" => "red" in limit_states,
      "yellow" => "yellow" in limit_states,
      "blue" => "blue" in limit_states
    }

    conditions_item_pattern = Map.get(conditions_params, "item_name_pattern", "")

    # Merge conditions into params
    alarm_rule_params = Map.put(alarm_rule_params, "conditions", conditions)

    changeset =
      socket.assigns.alarm_rule
      |> AlarmRule.changeset(alarm_rule_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:conditions_limit_states, conditions_limit_states)
     |> assign(:conditions_item_pattern, conditions_item_pattern)
     |> assign_form(changeset)}
  end

  def handle_event("save", params, socket) do
    alarm_rule_params = Map.get(params, "alarm_rule", %{})
    conditions_params = Map.get(params, "conditions", %{})
    conditions = build_conditions(conditions_params)

    alarm_rule_params = Map.put(alarm_rule_params, "conditions", conditions)

    save_alarm_rule(socket, socket.assigns.action, alarm_rule_params)
  end

  def handle_event("delete", _params, socket) do
    case Alarms.delete_rule(socket.assigns.alarm_rule) do
      {:ok, _} ->
        notify_parent({:deleted, socket.assigns.alarm_rule})

        {:noreply,
         socket
         |> put_flash(:info, "Alarm rule deleted")
         |> push_patch(to: socket.assigns.patch)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete alarm rule")}
    end
  end

  defp save_alarm_rule(socket, :edit, params) do
    case Alarms.update_rule(socket.assigns.alarm_rule, params) do
      {:ok, alarm_rule} ->
        notify_parent({:saved, alarm_rule})
        invalidate_rule_cache(socket.assigns.mission.id)

        {:noreply,
         socket
         |> put_flash(:info, "Alarm rule updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_alarm_rule(socket, :new, params) do
    params =
      params
      |> Map.put("organization_id", socket.assigns.mission.organization_id)
      |> Map.put("mission_id", socket.assigns.mission.id)

    case Alarms.create_rule(params) do
      {:ok, alarm_rule} ->
        notify_parent({:saved, alarm_rule})
        invalidate_rule_cache(socket.assigns.mission.id)

        {:noreply,
         socket
         |> put_flash(:info, "Alarm rule created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp build_conditions(params) do
    conditions = %{}

    # Add limit_state if any selected
    limit_states = Map.get(params, "limit_state", [])

    conditions =
      if limit_states != [] do
        Map.put(conditions, "limit_state", limit_states)
      else
        conditions
      end

    # Add item_name_pattern if provided
    pattern = Map.get(params, "item_name_pattern", "")

    conditions =
      if pattern != "" do
        Map.put(conditions, "item_name_pattern", pattern)
      else
        conditions
      end

    conditions
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp invalidate_rule_cache(mission_id) do
    # Notify the rule cache to refresh
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "alarm_rules:changed",
      {:rule_changed, mission_id}
    )
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
