defmodule CadenceWeb.OpsConsoleLive.Widgets.ProcedureWidget do
  @moduledoc """
  Phoenix LiveComponent for displaying procedure execution status.

  Shows:
  - Progress bar with step count
  - Step list with status icons
  - Elapsed time (via JavaScript hook)
  - Control buttons (pause/resume/abort)
  - Log tail

  ## Usage

      <.live_component
        module={ProcedureWidget}
        id="proc-widget-1"
        widget_id="widget-def"
        execution={@execution}
        config={%{
          "show_logs" => true,
          "max_log_lines" => 10
        }}
        on_configure={JS.push("open_widget_config")}
        on_pause={JS.push("pause_procedure")}
        on_resume={JS.push("resume_procedure")}
        on_abort={JS.push("abort_procedure")}
      />
  """
  use CadenceWeb, :live_component

  import CadenceWeb.WidgetComponents

  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    config = assigns[:config] || %{}
    execution = assigns[:execution]
    title = config["title"] || (execution && execution.procedure_name) || "Procedure"
    show_logs = config["show_logs"] != false
    max_log_lines = config["max_log_lines"] || 10

    # Calculate progress
    {current_step, total_steps, progress_pct} = calculate_progress(execution)

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:show_logs, show_logs)
      |> assign(:max_log_lines, max_log_lines)
      |> assign(:current_step, current_step)
      |> assign(:total_steps, total_steps)
      |> assign(:progress_pct, progress_pct)

    ~H"""
    <.widget
      id={@widget_id}
      title={@title}
      on_configure={
        @on_configure &&
          JS.push("open_widget_config", value: widget_config_value(@widget_id, "procedure", @config))
      }
    >
      <div class="procedure-widget">
        <%= if @execution do %>
          <!-- Progress header -->
          <div class="procedure-header mb-3">
            <div class="flex items-center justify-between mb-2">
              <div class="flex items-center gap-2">
                <.severity_dot
                  severity={status_severity(@execution.status)}
                  pulse={@execution.status == :running}
                />
                <span class="text-sm font-medium">{format_status(@execution.status)}</span>
              </div>
              <div
                id={"#{@widget_id}-elapsed"}
                class="text-xs text-base-content/50 font-mono"
                phx-hook="ProcedureElapsed"
                data-started-at={@execution.started_at && DateTime.to_iso8601(@execution.started_at)}
                data-status={@execution.status}
              >
                --:--
              </div>
            </div>
            
    <!-- Progress bar -->
            <div class="w-full bg-base-300 rounded-full h-1.5 mb-1">
              <div
                class="h-1.5 rounded-full bg-primary transition-all"
                style={"width: #{@progress_pct}%"}
              >
              </div>
            </div>
            <div class="text-xs text-base-content/50">
              Step {@current_step} of {@total_steps}
            </div>
          </div>
          
    <!-- Control buttons -->
          <div class="procedure-controls flex items-center gap-2 mb-3">
            <.widget_action_btn
              :if={@execution.status == :running && @on_pause}
              phx-click={JS.push("pause_procedure", value: %{id: @execution.id})}
            >
              <.icon name="hero-pause" class="w-3 h-3" /> Pause
            </.widget_action_btn>

            <.widget_action_btn
              :if={@execution.status == :paused && @on_resume}
              variant="success"
              phx-click={JS.push("resume_procedure", value: %{id: @execution.id})}
            >
              <.icon name="hero-play" class="w-3 h-3" /> Resume
            </.widget_action_btn>

            <.widget_action_btn
              :if={@execution.status in [:running, :paused] && @on_abort}
              variant="danger"
              phx-click={JS.push("abort_procedure", value: %{id: @execution.id})}
            >
              <.icon name="hero-stop" class="w-3 h-3" /> Abort
            </.widget_action_btn>
          </div>
          
    <!-- Step list -->
          <div class="procedure-steps flex-1 overflow-y-auto space-y-1 mb-3">
            <div
              :for={{step, idx} <- Enum.with_index(@execution.steps || [])}
              class={[
                "step-item flex items-center gap-2 p-1.5 rounded text-sm",
                step_bg_class(step, idx, @current_step - 1)
              ]}
            >
              <div class="step-indicator">
                {step_icon(step, idx, @current_step - 1)}
              </div>
              <span class="truncate flex-1">{step.name || "Step #{idx + 1}"}</span>
            </div>
          </div>
          
    <!-- Log tail -->
          <div
            :if={@show_logs && @execution.logs && length(@execution.logs) > 0}
            class="procedure-logs border-t border-base-300 pt-2"
          >
            <div class="text-xs text-base-content/40 mb-1">Recent logs</div>
            <div class="space-y-0.5 font-mono text-xs">
              <div
                :for={log <- Enum.take(@execution.logs, -@max_log_lines)}
                class={["log-line", log_level_class(log.level)]}
              >
                <span class="text-base-content/40">{format_log_time(log.timestamp)}</span>
                <span class="ml-2">{log.message}</span>
              </div>
            </div>
          </div>
        <% else %>
          <.widget_empty icon="hero-document-text" message="No procedure running" />
        <% end %>
      </div>
    </.widget>
    """
  end

  defp calculate_progress(nil), do: {0, 0, 0}

  defp calculate_progress(execution) do
    steps = execution.steps || []
    total = length(steps)

    if total == 0 do
      {0, 0, 0}
    else
      current = (execution.current_step_index || 0) + 1
      pct = round(current / total * 100)
      {current, total, pct}
    end
  end

  defp status_severity(:running), do: :info
  defp status_severity(:paused), do: :warning
  defp status_severity(:completed), do: :nominal
  defp status_severity(:failed), do: :critical
  defp status_severity(:cancelled), do: :critical
  defp status_severity(_), do: :info

  defp format_status(:running), do: "Running"
  defp format_status(:paused), do: "Paused"
  defp format_status(:completed), do: "Completed"
  defp format_status(:failed), do: "Failed"
  defp format_status(:cancelled), do: "Cancelled"
  defp format_status(:pending), do: "Pending"
  defp format_status(status), do: to_string(status)

  defp step_bg_class(_step, idx, current_idx) when idx < current_idx, do: "bg-success/10"
  defp step_bg_class(_step, idx, current_idx) when idx == current_idx, do: "bg-primary/10"
  defp step_bg_class(_step, _idx, _current_idx), do: ""

  defp step_icon(_step, idx, current_idx) when idx < current_idx do
    assigns = %{}

    ~H"""
    <.icon name="hero-check-circle" class="w-4 h-4 text-success" />
    """
  end

  defp step_icon(_step, idx, current_idx) when idx == current_idx do
    assigns = %{}

    ~H"""
    <.icon name="hero-arrow-right-circle" class="w-4 h-4 text-primary animate-pulse" />
    """
  end

  defp step_icon(_step, _idx, _current_idx) do
    assigns = %{}

    ~H"""
    <.icon name="hero-circle-stack" class="w-4 h-4 text-base-content/30" />
    """
  end

  defp log_level_class(:error), do: "text-error"
  defp log_level_class(:warning), do: "text-warning"
  defp log_level_class(:info), do: "text-info"
  defp log_level_class(_), do: "text-base-content/70"

  defp format_log_time(nil), do: "--:--:--"

  defp format_log_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_log_time(_), do: "--:--:--"

  defp widget_config_value(widget_id, widget_type, config) do
    %{widget_id: widget_id, widget_type: widget_type, config: config}
  end
end
