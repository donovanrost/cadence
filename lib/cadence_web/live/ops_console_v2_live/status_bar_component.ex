defmodule CadenceWeb.OpsConsoleV2Live.StatusBarComponent do
  @moduledoc """
  Global Status Bar for OPS Console V2.

  Always-visible strip at top showing:
  - Mission name and operational mode
  - Fleet health indicator
  - Alarm counts by severity
  - Running procedure count
  - Time displays (UTC, MET, Local)
  - Back to mission link
  """

  use CadenceWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <header class="status-bar flex items-center justify-between px-3 py-1.5 bg-base-200 border-b border-base-300 shrink-0">
      <!-- Left section: Mission info -->
      <div class="flex items-center gap-4">
        <!-- Back to mission -->
        <.link
          navigate={~p"/missions/#{@mission}"}
          class="flex items-center gap-1.5 text-xs text-base-content/50 hover:text-primary transition-colors"
          title="Back to Mission"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
        </.link>

        <!-- Mission name -->
        <div class="flex items-center gap-2">
          <span class="mc-label-subsystem text-base-content/40">MISSION</span>
          <span class="font-semibold text-sm text-primary tracking-wide">
            {@mission.name}
          </span>
          <span class="status-badge-nominal text-[0.65rem] px-1.5 py-0.5 rounded uppercase tracking-wide">
            NOMINAL
          </span>
        </div>
      </div>

      <!-- Center section: Fleet and Alarms -->
      <div class="flex items-center gap-6">
        <!-- Fleet health -->
        <div class="flex items-center gap-2" title="Fleet Health">
          <span class="mc-label-subsystem text-base-content/40">FLEET</span>
          <div class="flex items-center gap-1.5">
            <span class={[
              "font-mono font-medium text-sm",
              fleet_health_color(@fleet_health.percentage)
            ]}>
              {@fleet_health.percentage}%
            </span>
            <span class={[
              "w-2 h-2 rounded-full",
              fleet_health_indicator(@fleet_health.percentage)
            ]}>
            </span>
            <span class="text-xs text-base-content/50">
              ({@fleet_health.healthy}/{@fleet_health.total})
            </span>
          </div>
        </div>

        <!-- Alarm counts -->
        <div class="flex items-center gap-3" title="Active Alarms">
          <span class="mc-label-subsystem text-base-content/40">ALARMS</span>
          <div class="flex items-center gap-2">
            <!-- Critical -->
            <div class={[
              "flex items-center gap-1 px-2 py-0.5 rounded text-xs font-mono font-medium",
              if(@alarm_counts.critical > 0,
                do: "bg-error/20 text-error status-critical-pulse",
                else: "bg-base-300 text-base-content/40"
              )
            ]}>
              <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
              <span>{@alarm_counts.critical}</span>
              <span class="mc-label-subsystem">CRIT</span>
            </div>
            <!-- Warning -->
            <div class={[
              "flex items-center gap-1 px-2 py-0.5 rounded text-xs font-mono font-medium",
              if(@alarm_counts.warning > 0,
                do: "bg-warning/20 text-warning",
                else: "bg-base-300 text-base-content/40"
              )
            ]}>
              <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
              <span>{@alarm_counts.warning}</span>
              <span class="mc-label-subsystem">WARN</span>
            </div>
            <!-- Info -->
            <div class={[
              "flex items-center gap-1 px-2 py-0.5 rounded text-xs font-mono",
              if(@alarm_counts.info > 0,
                do: "bg-info/20 text-info",
                else: "bg-base-300 text-base-content/40"
              )
            ]}>
              <span>{@alarm_counts.info}</span>
              <span class="mc-label-subsystem">INFO</span>
            </div>
          </div>
        </div>

        <!-- Running procedures -->
        <div class="flex items-center gap-2" title="Running Procedures">
          <span class="mc-label-subsystem text-base-content/40">PROCS</span>
          <span class={[
            "font-mono text-sm",
            if(length(@running_procedures) > 0, do: "text-accent font-medium", else: "text-base-content/50")
          ]}>
            {length(@running_procedures)}
          </span>
        </div>
      </div>

      <!-- Right section: Time displays -->
      <div class="flex items-center gap-4">
        <!-- UTC Time -->
        <div class="flex items-center gap-2">
          <span class="mc-label-subsystem text-base-content/40">UTC</span>
          <span class="font-mono text-sm text-base-content">
            {format_utc_time(@current_time)}
          </span>
        </div>

        <!-- MET (Mission Elapsed Time) - placeholder -->
        <div class="flex items-center gap-2">
          <span class="mc-label-subsystem text-base-content/40">MET</span>
          <span class="font-mono text-sm text-base-content/70">
            {format_met(@mission)}
          </span>
        </div>

        <!-- Connection status indicator -->
        <div class="flex items-center gap-1.5" title="Connection Status">
          <span class="w-2 h-2 rounded-full bg-success animate-pulse"></span>
          <span class="mc-label-subsystem text-success">LIVE</span>
        </div>
      </div>
    </header>
    """
  end

  # Helper functions

  defp fleet_health_color(percentage) when percentage >= 95, do: "text-success"
  defp fleet_health_color(percentage) when percentage >= 80, do: "text-warning"
  defp fleet_health_color(_percentage), do: "text-error"

  defp fleet_health_indicator(percentage) when percentage >= 95, do: "bg-success"
  defp fleet_health_indicator(percentage) when percentage >= 80, do: "bg-warning animate-pulse"
  defp fleet_health_indicator(_percentage), do: "bg-error status-critical-pulse"

  defp format_utc_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_met(mission) do
    # Calculate elapsed time since mission start
    case mission.start_date do
      nil ->
        "---:--:--:--"

      start_date ->
        # Convert Date to DateTime at midnight UTC
        {:ok, started_at} = DateTime.new(start_date, ~T[00:00:00], "Etc/UTC")
        diff = DateTime.diff(DateTime.utc_now(), started_at, :second)

        # Handle negative diff (mission hasn't started yet)
        if diff < 0 do
          "T-#{format_countdown(-diff)}"
        else
          days = div(diff, 86400)
          hours = div(rem(diff, 86400), 3600)
          minutes = div(rem(diff, 3600), 60)
          seconds = rem(diff, 60)

          :io_lib.format("~3..0B:~2..0B:~2..0B:~2..0B", [days, hours, minutes, seconds])
          |> IO.iodata_to_binary()
        end
    end
  end

  defp format_countdown(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    :io_lib.format("~3..0B:~2..0B:~2..0B:~2..0B", [days, hours, minutes, secs])
    |> IO.iodata_to_binary()
  end
end
