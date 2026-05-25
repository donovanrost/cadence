defmodule CadenceWeb.SpacecraftTelemetryDecomLive.Components do
  @moduledoc false

  use CadenceWeb, :html

  import CadenceWeb.CoreComponents, only: [status_dot: 1]

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable

  attr :config, :any, default: nil
  attr :active, :any, default: nil
  attr :saved_at, :any, default: nil

  def status_section(assigns) do
    assigns = assign(assigns, :status, TelemetryDecom.status(assigns.config, assigns.active))

    ~H"""
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <.status_dot status={dot_status(@status)} />
        <span class="text-base-content/90">{status_label(@status)}</span>
        <span class="text-sm text-base-content/50">— {status_description(@status)}</span>
      </div>
      <span :if={@saved_at} class="hud-label">Saved {format_relative(@saved_at)}</span>
    </div>
    """
  end

  attr :revisions, :list, required: true
  attr :selected_revision_id, :any, default: nil

  def revision_section(assigns) do
    # Intentional UI-rule deviation: <.input> requires a FormField binding,
    # which is awkward for this standalone phx-change form. Raw <select>
    # uses the same daisyUI tokens as <.input>.
    ~H"""
    <div>
      <p class="hud-label mb-2">Catalog revision</p>
      <form phx-change="change_revision" id="telemetry-decom-revision-form" class="max-w-sm">
        <select
          name="catalog_revision_id"
          id="telemetry-decom-revision-select"
          class="select w-full"
        >
          <option
            :for={{label, value} <- @revisions}
            value={value}
            selected={to_string(@selected_revision_id) == to_string(value)}
          >
            {label}
          </option>
        </select>
      </form>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :selection, :any, required: true
  attr :conflicts, :map, required: true
  attr :expanded_apids, :any, required: true
  attr :filter, :string, required: true
  attr :points_by_id, :map, required: true

  def apid_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between gap-2">
        <p class="hud-label">
          Handled APIDs · {MapSet.size(@selection)} / {length(@rows)}
        </p>
        <div class="flex items-center gap-2">
          <form phx-change="filter_apids" id="telemetry-decom-filter-form">
            <%!-- Intentional UI-rule deviation: see revision_section/1. Raw <input>
            for the same FormField-binding reason. --%>
            <input
              type="text"
              name="filter"
              value={@filter}
              placeholder="Filter…"
              class="input input-sm"
              id="telemetry-decom-filter-input"
            />
          </form>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="select_all_unclaimed"
            id="telemetry-decom-select-all"
          >
            Select all unclaimed
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="clear_selection"
            id="telemetry-decom-clear"
          >
            Clear
          </button>
        </div>
      </div>
      <APIDTable.table
        rows={@rows}
        selection={@selection}
        conflicts={@conflicts}
        expanded_apids={@expanded_apids}
        filter={@filter}
        points_by_id={@points_by_id}
      />
    </div>
    """
  end

  attr :preview, :any, default: nil

  def preview_section(%{preview: nil} = assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Preview</p>
      <p class="text-sm text-base-content/60">
        Select one or more APIDs to preview matched packets.
      </p>
    </div>
    """
  end

  def preview_section(assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Preview</p>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
        <div>
          <div class="text-base-content/60">Matched packets</div>
          <div class="text-xl font-semibold">{length(@preview.selected_packets)}</div>
        </div>
        <div>
          <div class="text-base-content/60">Compiled defs</div>
          <div class="text-xl font-semibold">
            {length(@preview.compilation.compiler_result.packet_definitions)}
          </div>
        </div>
        <div>
          <div class="text-base-content/60">Unassigned APIDs</div>
          <div class="text-xl font-semibold">{length(@preview.unassigned_apids)}</div>
        </div>
        <div>
          <div class="text-base-content/60">Notices</div>
          <div class="text-xl font-semibold">
            {length(@preview.compilation.compiler_result.diagnostics)}
          </div>
        </div>
      </div>
      <.diagnostics_list diagnostics={@preview.compilation.compiler_result.diagnostics} />
    </div>
    """
  end

  attr :diagnostics, :list, default: []

  defp diagnostics_list(%{diagnostics: []} = assigns), do: ~H""

  defp diagnostics_list(assigns) do
    ~H"""
    <ul class="space-y-1 text-sm mt-3" id="telemetry-decom-diagnostics">
      <li :for={d <- Enum.take(@diagnostics, 20)} class="flex items-start gap-2">
        <.status_dot status={diagnostic_dot(d.severity)} size={:sm} class="mt-1.5" />
        <span>
          <span class="font-mono text-xs text-base-content/60">{d.code}</span>
          <span class="ml-1">{d.message}</span>
        </span>
      </li>
      <li :if={length(@diagnostics) > 20} class="text-xs text-base-content/60 mt-2">
        {length(@diagnostics) - 20} more omitted.
      </li>
    </ul>
    """
  end

  attr :config, :any, default: nil

  def apply_section(%{config: nil} = assigns) do
    ~H"""
    <div class="flex justify-end">
      <p class="text-sm text-base-content/60">
        Select at least one APID to save and apply.
      </p>
    </div>
    """
  end

  def apply_section(assigns) do
    ~H"""
    <div class="flex justify-end gap-2">
      <button
        :if={@config.enabled}
        type="button"
        class="btn btn-ghost btn-sm"
        phx-click="disable"
        id="telemetry-decom-disable-button"
        data-confirm="Disable telemetry interpretation for this spacecraft?"
      >
        Disable
      </button>
      <button
        type="button"
        class="btn btn-primary btn-sm"
        phx-click="enable"
        id="telemetry-decom-enable-button"
      >
        Apply mission changes
      </button>
    </div>
    """
  end

  attr :dropped, :list, default: []

  def dropped_unknowns_banner(%{dropped: []} = assigns), do: ~H""

  def dropped_unknowns_banner(assigns) do
    ~H"""
    <div class="alert alert-warning text-sm" id="telemetry-decom-dropped-unknowns">
      <span>
        {length(@dropped)} previously selected {if length(@dropped) == 1, do: "APID is", else: "APIDs are"}
        not in this revision:
        <span class="font-mono">{Enum.join(@dropped, ", ")}</span>.
      </span>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click="drop_unknown_apids"
        id="telemetry-decom-drop-unknowns"
      >
        Drop them
      </button>
    </div>
    """
  end

  attr :current_mission, :map, required: true

  def no_revisions_notice(assigns) do
    ~H"""
    <div>
      <p class="text-sm text-base-content/60">
        No telemetry catalog revisions available for this mission yet. Import a catalog
        revision first.
      </p>
      <.link
        navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
        class="btn btn-ghost btn-sm mt-3"
      >
        Go to catalog
      </.link>
    </div>
    """
  end

  defp dot_status(:applied), do: :ready
  defp dot_status(:configured), do: :info
  defp dot_status(:outdated), do: :attention
  defp dot_status(:disabled), do: :blocked
  defp dot_status(:not_configured), do: :blocked

  defp status_label(:applied), do: "Applied"
  defp status_label(:configured), do: "Configured — not yet applied"
  defp status_label(:outdated), do: "Applied configuration is out of date"
  defp status_label(:disabled), do: "Disabled"
  defp status_label(:not_configured), do: "Not configured"

  defp status_description(:applied),
    do: "This configuration is live on the mission."

  defp status_description(:configured),
    do: "Choices are saved. Apply mission changes to publish them."

  defp status_description(:outdated),
    do:
      "The saved configuration differs from what is live. Apply mission changes to publish the latest state."

  defp status_description(:disabled),
    do:
      "This spacecraft is excluded from telemetry interpretation. Apply mission changes to publish the disabled state."

  defp status_description(:not_configured),
    do: "Choose a catalog revision and handled APIDs, then apply mission changes."

  defp diagnostic_dot(:error), do: :blocked
  defp diagnostic_dot(:warning), do: :attention
  defp diagnostic_dot(_), do: :info

  defp format_relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
