defmodule CadenceWeb.SpacecraftTelemetryDecomLive.Components do
  @moduledoc false

  use CadenceWeb, :html

  alias Cadence.Applications.LifecycleContract
  alias Cadence.Applications.PreflightReport
  alias Cadence.Applications.SurfaceElements.{Diagnostic, Diagnostics}
  alias Cadence.Applications.TelemetryDecom

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
        <span class="text-sm text-base-content/70">— {status_description(@status)}</span>
      </div>
      <span :if={@saved_at} class="hud-label">Saved {format_relative(@saved_at)}</span>
    </div>
    """
  end

  attr :revisions, :list, required: true
  attr :selected_revision_id, :any, default: nil

  def revision_section(assigns) do
    ~H"""
    <form
      phx-change="change_revision"
      id="telemetry-decom-revision-form"
      class="flex max-w-xl items-end gap-3"
    >
      <.input
        type="select"
        id="telemetry-decom-revision-select"
        name="catalog_revision_id"
        label="Catalog revision"
        value={@selected_revision_id}
        options={@revisions}
      />
      <.button
        type="button"
        variant={:ghost}
        size={:sm}
        phx-click="save_catalog_revision"
        id="telemetry-decom-save-revision"
        class="mb-3 shrink-0"
      >
        Use revision
      </.button>
    </form>
    """
  end

  attr :rows, :list, required: true
  attr :selection, :any, required: true
  attr :mission, :map, required: true
  attr :spacecraft, :map, required: true

  def packet_bindings_handoff(assigns) do
    ~H"""
    <section id="telemetry-decom-packet-bindings-handoff" class="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-center">
      <div>
        <p class="hud-label">Packet inputs</p>
        <p class="mt-2 text-sm text-base-content/70">
          {MapSet.size(@selection)} of {length(@rows)} packet selectors currently feed Telemetry Decom.
          Packet and field selection now lives in the shared host surface.
        </p>
        <p class="mt-1 text-xs text-base-content/50">
          APIDs route traffic; other applications may read the same packets and fields.
        </p>
      </div>
      <.button
        navigate={~p"/missions/#{@mission.mission_id}/spacecraft/#{@spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"}
        variant={:ghost}
        id="telemetry-decom-open-packet-bindings"
      >
        Open Packet Bindings
      </.button>
    </section>
    """
  end

  attr :preview, :any, default: nil

  def preview_section(%{preview: nil} = assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Preview</p>
      <p class="text-sm text-base-content/70">
        Select one or more packet APIDs to preview the application input binding.
      </p>
    </div>
    """
  end

  def preview_section(assigns) do
    assigns =
      assign(
        assigns,
        :diagnostics,
        compiler_diagnostics(assigns.preview.compilation.compiler_result.diagnostics)
      )

    ~H"""
    <div>
      <p class="hud-label mb-2">Preview</p>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <.stat_tile label="Matched packets" value={length(@preview.selected_packets)} />
        <.stat_tile
          label="Compiled defs"
          value={length(@preview.compilation.compiler_result.packet_definitions)}
        />
        <.stat_tile label="Unassigned APIDs" value={length(@preview.unassigned_apids)} />
        <.stat_tile
          label="Notices"
          value={length(@preview.compilation.compiler_result.diagnostics)}
        />
      </div>
      <div :if={@diagnostics} class="mt-3">
        <.application_diagnostics definition={@diagnostics} />
      </div>
    </div>
    """
  end

  attr :config, :any, default: nil
  attr :pending_activation_request, :any, default: nil
  attr :preflight, PreflightReport, required: true
  attr :lifecycle_contract, LifecycleContract, required: true

  def apply_section(%{config: nil} = assigns) do
    ~H"""
    <div class="flex justify-end">
      <p class="text-sm text-base-content/70">
        Select at least one APID to save and apply.
      </p>
    </div>
    """
  end

  def apply_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <.callout
        :if={@pending_activation_request}
        variant={:info}
        id="telemetry-decom-activation-pending"
      >
        Activation request
        <span class="font-mono">{@pending_activation_request.activation_request_id}</span>
        is waiting for approval from a different mission administrator.
      </.callout>
      <div class="flex justify-end gap-2">
        <.application_lifecycle_action
          :if={@config.enabled}
          action_id="disable"
          contract={@lifecycle_contract}
          event="disable"
          id="telemetry-decom-disable-button"
        />
        <.application_lifecycle_action
          action_id="request_activation"
          contract={@lifecycle_contract}
          event="enable"
          id="telemetry-decom-enable-button"
          disabled={
            not is_nil(@pending_activation_request) or not PreflightReport.ready?(@preflight)
          }
        />
      </div>
    </div>
    """
  end

  attr :current_mission, :map, required: true

  def no_revisions_notice(assigns) do
    ~H"""
    <div>
      <p class="text-sm text-base-content/70">
        No packet catalog revisions are available for this mission yet. Import a catalog
        revision first.
      </p>
      <.button
        navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
        variant={:ghost}
        class="mt-3"
      >
        Go to catalog
      </.button>
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
    do: "Choices are saved. Request mission changes to publish them."

  defp status_description(:outdated),
    do:
      "The saved configuration differs from what is live. Request mission changes to publish the latest state."

  defp status_description(:disabled),
    do:
      "This spacecraft is excluded from Telemetry Decom. Request mission changes to publish the disabled state."

  defp status_description(:not_configured),
    do: "Choose a catalog revision and packet inputs, then apply mission changes."

  defp compiler_diagnostics([]), do: nil

  defp compiler_diagnostics(diagnostics) do
    items =
      diagnostics
      |> Enum.sort_by(fn diagnostic ->
        {severity_rank(diagnostic.severity), diagnostic.code, diagnostic.path}
      end)
      |> Enum.take(20)
      |> Enum.with_index(1)
      |> Enum.map(fn {diagnostic, index} ->
        %Diagnostic{
          id: "compiler-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}",
          code: diagnostic.code,
          severity: diagnostic.severity,
          title: diagnostic_title(diagnostic.code),
          detail: diagnostic.message,
          value: diagnostic_path(diagnostic.path)
        }
      end)

    %Diagnostics{
      id: "telemetry-decom-diagnostics",
      title: "Compiler findings",
      description: "Exceptional conditions from the selected packet compilation preview.",
      items: items,
      total_count: length(diagnostics)
    }
  end

  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2

  defp diagnostic_title(code) do
    code
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp diagnostic_path([]), do: nil
  defp diagnostic_path(path), do: Enum.join(path, " / ")

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
