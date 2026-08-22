defmodule CadenceWeb.CommandLive.Sender do
  @moduledoc """
  LiveView for sending commands to spacecraft targets.

  Commands are loaded from the selected target's definition_set_id, ensuring
  each target uses its correct command dictionary version.

  Provides a UI for:
  - Selecting a target
  - Selecting commands from the target's command database
  - Filling in command arguments
  - Reviewing and sending commands
  - Confirming hazardous commands
  - Viewing command status and verification results
  """

  use CadenceWeb, :live_view

  alias Cadence.{Commands, Missions, Targets}
  alias Cadence.MissionDatabase.MetaCommand

  @impl true
  def mount(%{"mission_id" => mission_id}, _session, socket) do
    # Use unscoped - authorization is handled via LiveView hooks
    mission = Missions.get_mission!(mission_id)
    targets = Targets.list_targets(mission)

    {:ok,
     socket
     |> assign(:page_title, "Command Sender")
     |> assign(:mission, mission)
     |> assign(:targets, targets)
     |> assign(:commands, [])
     |> assign(:selected_command, nil)
     |> assign(:selected_target, nil)
     |> assign(:param_form, nil)
     |> assign(:pending_confirmation, nil)
     |> assign(:last_result, nil)
     |> assign(:command_history, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <.header>
        Command Sender
        <:subtitle>
          Mission: {@mission.name} ({@mission.phase})
        </:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mt-6">
        <%!-- Command Selection Panel --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-sm uppercase tracking-wide text-base-content/70">
              Select Command
            </h2>

            <.input
              name="target"
              type="select"
              label="Target"
              prompt="Select target..."
              options={target_options(@targets)}
              value={@selected_target && @selected_target.id}
              phx-change="select_target"
            />

            <div class="divider my-2"></div>

            <%= if @selected_target do %>
              <div class="max-h-96 overflow-y-auto">
                <ul class="menu menu-sm bg-base-100 rounded-lg">
                  <%= for command <- @commands do %>
                    <li>
                      <a
                        phx-click="select_command"
                        phx-value-id={command.id}
                        class={[
                          @selected_command && @selected_command.id == command.id && "active"
                        ]}
                      >
                        <span class="flex items-center gap-2">
                          <.icon
                            :if={command.is_hazardous}
                            name="hero-exclamation-triangle"
                            class="size-4 text-warning"
                          />
                          {command.name}
                        </span>
                        <span class="text-xs text-base-content/50">
                          0x{Integer.to_string(command.opcode || 0, 16) |> String.pad_leading(4, "0")}
                        </span>
                      </a>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% else %>
              <div class="text-sm text-base-content/50 italic text-center py-4">
                Select a target to see available commands
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Command Parameters Panel --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-sm uppercase tracking-wide text-base-content/70">
              Arguments
            </h2>

            <%= if @selected_command do %>
              <div class="mb-4">
                <div class="flex items-center gap-2">
                  <span class="font-bold">{@selected_command.name}</span>
                  <.badge :if={@selected_command.is_hazardous} variant="warning">
                    Hazardous
                  </.badge>
                </div>
                <p :if={@selected_command.description} class="text-sm text-base-content/70 mt-1">
                  {@selected_command.description}
                </p>
              </div>

              <.simple_form
                :if={@param_form}
                for={@param_form}
                id="command-params-form"
                phx-change="validate_params"
                phx-submit="send_command"
              >
                <%= for arg <- @selected_command.arguments do %>
                  <.arg_input arg={arg} form={@param_form} />
                <% end %>

                <%= if Enum.empty?(@selected_command.arguments) do %>
                  <p class="text-sm text-base-content/50 italic">
                    This command has no arguments.
                  </p>
                <% end %>

                <:actions>
                  <button
                    type="submit"
                    class={[
                      "btn w-full mt-4",
                      @selected_command.is_hazardous && "btn-warning",
                      !@selected_command.is_hazardous && "btn-primary"
                    ]}
                    disabled={is_nil(@selected_target)}
                  >
                    <.icon name="hero-paper-airplane" class="size-4" />
                    <%= if @selected_command.is_hazardous do %>
                      Send Hazardous Command
                    <% else %>
                      Send Command
                    <% end %>
                  </button>
                </:actions>
              </.simple_form>
            <% else %>
              <div class="flex items-center justify-center h-48 text-base-content/50">
                Select a command from the list
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Status & History Panel --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-sm uppercase tracking-wide text-base-content/70">
              Status
            </h2>

            <%= if @last_result do %>
              <div class={[
                "alert mb-4",
                @last_result.success && "alert-success",
                !@last_result.success && "alert-error"
              ]}>
                <.icon
                  name={if @last_result.success, do: "hero-check-circle", else: "hero-x-circle"}
                  class="size-5"
                />
                <div>
                  <div class="font-bold">{@last_result.command_name}</div>
                  <div class="text-sm">{@last_result.message}</div>
                </div>
              </div>
            <% end %>

            <h3 class="font-semibold text-sm mt-4 mb-2">Recent Commands</h3>
            <div class="max-h-64 overflow-y-auto">
              <%= if Enum.empty?(@command_history) do %>
                <p class="text-sm text-base-content/50 italic">
                  No commands sent yet
                </p>
              <% else %>
                <ul class="timeline timeline-vertical timeline-compact">
                  <%= for entry <- @command_history do %>
                    <li>
                      <div class="timeline-start text-xs text-base-content/50">
                        {format_time(entry.sent_at)}
                      </div>
                      <div class={[
                        "timeline-middle",
                        entry.success && "text-success",
                        !entry.success && "text-error"
                      ]}>
                        <.icon
                          name={if entry.success, do: "hero-check-circle", else: "hero-x-circle"}
                          class="size-4"
                        />
                      </div>
                      <div class="timeline-end timeline-box text-sm">
                        {entry.command_name}
                      </div>
                      <hr />
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <%!-- Hazardous Confirmation Modal --%>
      <.modal
        :if={@pending_confirmation}
        id="hazard-confirmation-modal"
        show={true}
        on_cancel={JS.push("cancel_confirmation")}
      >
        <.live_component
          module={CadenceWeb.CommandLive.HazardConfirmationComponent}
          id="hazard-confirmation"
          mission_id={@mission.id}
          target_id={@pending_confirmation.target_id}
          command_name={@pending_confirmation.command_name}
          hazard_description={@pending_confirmation.hazard_description}
          token={@pending_confirmation.token}
          expires_at={@pending_confirmation.expires_at}
        />
      </.modal>
    </div>
    """
  end

  # Component for rendering argument inputs based on data type
  defp arg_input(assigns) do
    ~H"""
    <div class="mb-3">
      <%= case @arg.data_type_ref do %>
        <% "boolean" -> %>
          <.input
            field={@form[@arg.name]}
            type="checkbox"
            label={arg_label(@arg)}
          />
        <% "bool" -> %>
          <.input
            field={@form[@arg.name]}
            type="checkbox"
            label={arg_label(@arg)}
          />
        <% "enum" -> %>
          <.input
            field={@form[@arg.name]}
            type="select"
            label={arg_label(@arg)}
            options={@arg.valid_values || []}
            prompt="Select..."
          />
        <% type when type in ["int", "uint", "float"] -> %>
          <.input
            field={@form[@arg.name]}
            type="number"
            label={arg_label(@arg)}
            step={if type == "float", do: "any", else: "1"}
          />
        <% _ -> %>
          <.input
            field={@form[@arg.name]}
            type="text"
            label={arg_label(@arg)}
          />
      <% end %>
      <p :if={@arg.description} class="text-xs text-base-content/50 mt-1">
        {@arg.description}
      </p>
    </div>
    """
  end

  defp arg_label(arg) do
    required_mark = if arg.required, do: " *", else: ""
    "#{arg.name}#{required_mark}"
  end

  @impl true
  def handle_event("select_target", %{"target" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_target, nil)
     |> assign(:commands, [])
     |> assign(:selected_command, nil)
     |> assign(:param_form, nil)}
  end

  def handle_event("select_target", %{"target" => target_id}, socket) do
    target = Targets.get_target_with_definition_set!(target_id)

    # Load commands from the target's definition set
    commands =
      if target.definition_set_id do
        Commands.list_meta_commands(target.definition_set_id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_target, target)
     |> assign(:commands, commands)
     |> assign(:selected_command, nil)
     |> assign(:param_form, nil)}
  end

  def handle_event("select_command", %{"id" => command_id}, socket) do
    command = Commands.get_meta_command_by_id!(command_id)
    form = build_param_form(command)

    {:noreply,
     socket
     |> assign(:selected_command, command)
     |> assign(:param_form, form)}
  end

  def handle_event("validate_params", %{"params" => params}, socket) do
    form = to_form(params, as: :params)
    {:noreply, assign(socket, :param_form, form)}
  end

  def handle_event("validate_params", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("send_command", %{"params" => params}, socket) do
    send_command(socket, params)
  end

  def handle_event("send_command", _params, socket) do
    # No params case
    send_command(socket, %{})
  end

  def handle_event("cancel_confirmation", _params, socket) do
    {:noreply, assign(socket, :pending_confirmation, nil)}
  end

  @impl true
  def handle_info({:command_confirmed, command_log_id}, socket) do
    command_name = socket.assigns.pending_confirmation.command_name

    result = %{
      success: true,
      command_name: command_name,
      message: "Command sent (ID: #{String.slice(command_log_id, 0, 8)}...)",
      sent_at: DateTime.utc_now()
    }

    {:noreply,
     socket
     |> assign(:pending_confirmation, nil)
     |> assign(:last_result, result)
     |> update(:command_history, fn history ->
       [result | history] |> Enum.take(10)
     end)}
  end

  def handle_info(:confirmation_cancelled, socket) do
    {:noreply, assign(socket, :pending_confirmation, nil)}
  end

  def handle_info({:confirmation_error, message}, socket) do
    command_name = socket.assigns.pending_confirmation.command_name

    result = %{
      success: false,
      command_name: command_name,
      message: message,
      sent_at: DateTime.utc_now()
    }

    {:noreply,
     socket
     |> assign(:pending_confirmation, nil)
     |> assign(:last_result, result)
     |> update(:command_history, fn history ->
       [result | history] |> Enum.take(10)
     end)}
  end

  # Private functions

  defp send_command(socket, params) do
    command = socket.assigns.selected_command
    target = socket.assigns.selected_target
    user = socket.assigns.current_user

    if is_nil(target) do
      {:noreply, put_flash(socket, :error, "Please select a target")}
    else
      opts = [
        target: target.id,
        user_id: user && user.id
      ]

      case Commands.dispatch(socket.assigns.mission.id, command.name, params, opts) do
        {:ok, command_log_id} ->
          result =
            command_result(
              true,
              command.name,
              "Command sent (ID: #{String.slice(command_log_id, 0, 8)}...)"
            )

          {:noreply, put_command_result(socket, result)}

        {:error, :requires_confirmation, info} ->
          {:noreply, assign(socket, :pending_confirmation, info)}

        {:error, :not_allowed_in_phase, current_phase} ->
          result =
            command_result(
              false,
              command.name,
              "Command not allowed in #{current_phase} phase"
            )

          {:noreply, put_command_result(socket, result)}

        {:error, :validation_failed, errors} ->
          error_msg = format_validation_errors(errors)
          result = command_result(false, command.name, "Validation failed: #{error_msg}")
          {:noreply, put_command_result(socket, result)}

        {:error, reason} ->
          result = command_result(false, command.name, "Error: #{inspect(reason)}")
          {:noreply, put_command_result(socket, result)}
      end
    end
  end

  defp build_param_form(%MetaCommand{arguments: args}) do
    defaults =
      args
      |> Enum.map(fn arg -> {arg.name, arg.default_value} end)
      |> Map.new()

    to_form(defaults, as: :params)
  end

  defp target_options(targets) do
    Enum.map(targets, fn t -> {t.name, t.id} end)
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp command_result(success, command_name, message) do
    %{
      success: success,
      command_name: command_name,
      message: message,
      sent_at: DateTime.utc_now()
    }
  end

  defp put_command_result(socket, result) do
    socket
    |> assign(:last_result, result)
    |> update(:command_history, fn history ->
      [result | history] |> Enum.take(10)
    end)
  end

  defp format_validation_errors(errors) do
    Enum.map_join(errors, ", ", fn {field, msg} -> "#{field}: #{msg}" end)
  end
end
