defmodule CadenceWeb.OpsConsoleLive.Widgets.CommandWidget do
  @moduledoc """
  Phoenix LiveComponent for quick command execution.

  Displays a button to execute a single command with:
  - Hazardous command confirmation flow
  - Status indicator (idle/pending/sent/failed)
  - Last execution timestamp

  ## Usage

      <.live_component
        module={CommandWidget}
        id="cmd-widget-1"
        widget_id="widget-456"
        config={%{
          "target_id" => "target-123",
          "target_name" => "SAT-1",
          "command_name" => "SAFE_MODE",
          "label" => "SAFE MODE",
          "hazardous" => true,
          "description" => "Put satellite into safe mode"
        }}
        on_configure={JS.push("open_widget_config")}
        on_execute={JS.push("cmd_dispatch")}
      />
  """
  use CadenceWeb, :live_component

  import CadenceWeb.WidgetComponents

  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       status: :idle,
       last_execution: nil,
       last_error: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("execute", _params, socket) do
    config = socket.assigns.config || %{}
    hazardous = config["hazardous"] || false

    socket =
      if hazardous && socket.assigns.status != :confirming do
        # First click on hazardous - enter confirmation mode
        assign(socket, status: :confirming)
      else
        # Execute the command (non-hazardous or second click to confirm)
        execute_command(socket)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, status: :idle)}
  end

  defp execute_command(socket) do
    config = socket.assigns.config || %{}

    # Send event to parent LiveView
    send(self(), {:widget_command, socket.assigns.widget_id, %{
      target_id: config["target_id"],
      command_name: config["command_name"],
      parameters: config["parameters"] || %{}
    }})

    socket
    |> assign(status: :pending)
    |> assign(last_execution: DateTime.utc_now())
  end

  # Called by parent to update status
  def set_result(socket, success, error \\ nil) do
    status = if success, do: :sent, else: :failed

    socket
    |> assign(status: status)
    |> assign(last_error: error)
  end

  @impl true
  def render(assigns) do
    config = assigns[:config] || %{}
    target_name = config["target_name"] || "TARGET"
    command_name = config["command_name"]
    label = config["label"] || command_name || "EXECUTE"
    hazardous = config["hazardous"] || false
    description = config["description"]
    title = config["title"] || label

    status_info = status_display(assigns.status)

    assigns =
      assigns
      |> assign(:target_name, target_name)
      |> assign(:command_name, command_name)
      |> assign(:label, label)
      |> assign(:hazardous, hazardous)
      |> assign(:description, description)
      |> assign(:title, title)
      |> assign(:status_info, status_info)

    ~H"""
    <.widget
      id={@widget_id}
      title={@title}
      on_configure={@on_configure && JS.push("open_widget_config", value: widget_config_value(@widget_id, "command", @config))}
    >
      <div class="command-widget">
        <!-- Command info -->
        <div class="command-info mb-3">
          <div class="flex items-center gap-2 mb-1">
            <.icon :if={@hazardous} name="hero-exclamation-triangle" class="w-4 h-4 text-error" />
            <span class="mc-label-subsystem text-base-content/40">{@target_name}</span>
          </div>
          <div class="text-sm text-base-content/70 truncate" title={@command_name}>
            {@command_name || "No command configured"}
          </div>
          <div :if={@description} class="text-xs text-base-content/50 mt-1">{@description}</div>
        </div>

        <!-- Execute button -->
        <div class="command-action flex-1 flex flex-col items-center justify-center">
          <.command_btn
            status={@status}
            hazardous={@hazardous}
            disabled={!@command_name}
            phx-click="execute"
            phx-target={@myself}
          >
            {@label}
          </.command_btn>

          <div :if={@hazardous && @status == :confirming} class="confirm-prompt mt-2 text-center">
            <span class="text-warning text-xs">Click again to confirm</span>
            <button
              type="button"
              class="btn btn-xs btn-ghost ml-2"
              phx-click="cancel"
              phx-target={@myself}
            >
              Cancel
            </button>
          </div>
        </div>

        <!-- Status footer -->
        <div class="command-status mt-3 pt-2 border-t border-base-300">
          <div class="flex items-center justify-between">
            <.status_indicator status={@status_info.status} label={@status_info.label} pulse={@status == :pending} />
            <span :if={@last_execution} class="text-xs text-base-content/40">
              {format_time(@last_execution)}
            </span>
          </div>
          <div :if={@last_error} class="text-xs text-error mt-1 truncate" title={@last_error}>
            {@last_error}
          </div>
        </div>
      </div>
    </.widget>
    """
  end

  defp status_display(:idle), do: %{status: :idle, label: "Ready"}
  defp status_display(:confirming), do: %{status: :warning, label: "Awaiting confirmation"}
  defp status_display(:pending), do: %{status: :pending, label: "Sending..."}
  defp status_display(:sent), do: %{status: :nominal, label: "Sent"}
  defp status_display(:verified), do: %{status: :nominal, label: "Verified"}
  defp status_display(:failed), do: %{status: :critical, label: "Failed"}
  defp status_display(_), do: %{status: :idle, label: "Ready"}

  defp widget_config_value(widget_id, widget_type, config) do
    %{widget_id: widget_id, widget_type: widget_type, config: config}
  end

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end
end
