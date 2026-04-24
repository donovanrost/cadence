defmodule CadenceWeb.SpacecraftTelemetryDecomLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.Catalog

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id
    spacecraft_id = socket.assigns.current_spacecraft.spacecraft_id

    config =
      case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft_id) do
        {:ok, config} -> config
        {:error, :not_configured} -> nil
      end

    revisions = list_telemetry_revisions(organization_id, mission_id)
    selected_revision_id = (config && config.catalog_revision_id) || first_option_value(revisions)

    apid_rows = load_apid_rows(organization_id, mission_id, selected_revision_id)
    conflicts = TelemetryDecom.list_apid_conflicts(organization_id, mission_id, spacecraft_id)
    selection = selection_from_config(config)

    {:ok,
     socket
     |> assign(:page_title, "Telemetry Decom")
     |> assign(:nav_item, :spacecraft)
     |> assign(:config, config)
     |> assign(:revisions, revisions)
     |> assign(:selected_revision_id, selected_revision_id)
     |> assign(:apid_rows, apid_rows)
     |> assign(:conflicts, conflicts)
     |> assign(:selection, selection)
     |> assign(:expanded_apids, MapSet.new())
     |> assign(:expanded_defs, MapSet.new())
     |> assign(:expanded_entries, MapSet.new())
     |> assign(:filter, "")
     |> assign(:dropped_unknowns, [])
     |> assign(:preview, preview_for(organization_id, mission_id, config))
     |> assign(:active_binding_set_summary, fetch_active_binding_set_summary(mission_id))
     |> assign(:saved_at, config && DateTime.utc_now())
     |> assign_config_form(defaults_for(config, revisions))}
  end

  defp load_apid_rows(_organization_id, _mission_id, nil), do: []

  defp load_apid_rows(organization_id, mission_id, revision_id) do
    case TelemetryDecom.list_revision_apid_rows(organization_id, mission_id, revision_id) do
      {:ok, rows} -> rows
      {:error, _} -> []
    end
  end

  defp selection_from_config(nil), do: MapSet.new()
  defp selection_from_config(%{handled_apids: apids}), do: MapSet.new(apids)

  @impl true
  def handle_event("validate", %{"config" => params}, socket) do
    {:noreply, assign_config_form(socket, params)}
  end

  def handle_event(
        "save",
        %{"config" => params},
        %{assigns: %{current_scope: scope, current_mission: mission, current_spacecraft: sc}} =
          socket
      ) do
    case TelemetryDecom.configure(scope.organization_id, mission.mission_id, sc.spacecraft_id,
           catalog_revision_id: params["catalog_revision_id"],
           handled_apids: params["handled_apids"]
         ) do
      {:ok, config} ->
        preview = preview_for(scope.organization_id, mission.mission_id, config)

        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:preview, preview)
         |> assign_config_form(defaults_for(config, socket.assigns.revisions))
         |> put_flash(:info, "Telemetry Decom configuration saved.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign_config_form(params)
         |> put_flash(:error, "Could not save configuration: #{humanize_error(reason)}")}
    end
  end

  def handle_event(
        "enable",
        _params,
        %{assigns: %{current_scope: scope, current_mission: mission, current_spacecraft: sc}} =
          socket
      ) do
    case TelemetryDecom.apply_mission(
           scope.organization_id,
           mission.mission_id,
           sc.spacecraft_id
         ) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(
           :active_binding_set_summary,
           fetch_active_binding_set_summary(mission.mission_id)
         )
         |> put_flash(
           :info,
           "Telemetry Decom mission changes applied. All enabled spacecraft configurations are now live."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not enable: #{humanize_error(reason)}")}
    end
  end

  def handle_event(
        "disable",
        _params,
        %{assigns: %{current_scope: scope, current_mission: mission, current_spacecraft: sc}} =
          socket
      ) do
    case TelemetryDecom.disable(scope.organization_id, mission.mission_id, sc.spacecraft_id) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> put_flash(
           :info,
           "Telemetry Decom disabled for this spacecraft. Apply mission changes to remove it from the live mission."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not disable: #{humanize_error(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"
          }
          class="text-sm text-primary hover:underline"
        >
          &larr; {@current_spacecraft.display_name}
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">Telemetry Decom</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Choose the catalog revision and handled APIDs used to decode telemetry for
          <span class="font-semibold text-base-content"> {@current_spacecraft.display_name}</span>.
        </p>
      </div>

      <.status_card config={@config} active={@active_binding_set_summary} />

      <div class="card bg-base-200" id="telemetry-decom-config-card">
        <div class="card-body p-6 space-y-4">
          <p class="hud-label">Configuration</p>

          <%= if @revisions == [] do %>
            <p class="text-sm text-base-content/60">
              No telemetry catalog revisions available for this mission yet. Import a catalog
              revision first.
            </p>
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
              class="btn btn-ghost btn-sm self-start"
            >
              Go to catalog
            </.link>
          <% else %>
            <.form for={@config_form} phx-change="validate" phx-submit="save" id="telemetry-decom-config-form">
              <.input
                field={@config_form[:catalog_revision_id]}
                type="select"
                label="Catalog Revision"
                options={@revisions}
                required
              />
              <.input
                field={@config_form[:handled_apids]}
                type="text"
                label="Handled APIDs"
                placeholder="1, 2, 5-8, 42"
                required
              />
              <p class="text-sm text-base-content/60 -mt-2">
                Enter a comma-separated list of APIDs and ranges. Example:
                <span class="font-mono"> 1, 2, 5-8</span>
              </p>

              <button
                type="submit"
                class="btn btn-primary btn-sm"
                id="telemetry-decom-save-button"
              >
                Save configuration
              </button>
            </.form>
          <% end %>
        </div>
      </div>

      <.preview_card preview={@preview} current_mission={@current_mission} />

      <.actions_card config={@config} />
    </div>
    """
  end

  attr :config, :any, default: nil
  attr :active, :any, default: nil

  defp status_card(assigns) do
    assigns = assign(assigns, :status, TelemetryDecom.status(assigns.config, assigns.active))

    ~H"""
    <div class="card bg-base-200" id="telemetry-decom-status-card">
      <div class="card-body p-6">
        <p class="hud-label">Status</p>
        <div class="flex items-center gap-2 mt-3">
          <.status_dot status={dot_status(@status)} />
          <span class="text-base-content font-semibold">{status_label(@status)}</span>
        </div>
        <p class="text-sm text-base-content/60 mt-2">{status_description(@status)}</p>
      </div>
    </div>
    """
  end

  attr :preview, :any, default: nil
  attr :current_mission, :map, required: true

  defp preview_card(%{preview: nil} = assigns), do: ~H""

  defp preview_card(assigns) do
    ~H"""
    <div class="card bg-base-200" id="telemetry-decom-preview-card">
      <div class="card-body p-6 space-y-4">
        <p class="hud-label">Packet Definitions</p>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
          <div>
            <div class="text-base-content/60">Handled APIDs</div>
            <div class="text-xl font-semibold">{length(@preview.config.handled_apids)}</div>
          </div>
          <div>
            <div class="text-base-content/60">Matched Packets</div>
            <div class="text-xl font-semibold">{length(@preview.selected_packets)}</div>
          </div>
          <div>
            <div class="text-base-content/60">Compiled</div>
            <div class="text-xl font-semibold">
              {length(@preview.compilation.compiler_result.packet_definitions)}
            </div>
          </div>
          <div>
            <div class="text-base-content/60">Unassigned APIDs</div>
            <div class="text-xl font-semibold">{length(@preview.unassigned_apids)}</div>
          </div>
        </div>

        <div class="text-sm space-y-2">
          <p>
            <span class="text-base-content/60">Handled APIDs:</span>
            <span class="font-mono">{format_apids(@preview.config.handled_apids)}</span>
          </p>
          <p :if={@preview.unassigned_apids != []}>
            <span class="text-base-content/60">Unassigned APIDs in this revision:</span>
            <span class="font-mono">{format_apids(@preview.unassigned_apids)}</span>
          </p>
        </div>

        <.diagnostics_list diagnostics={@preview.compilation.compiler_result.diagnostics} />
      </div>
    </div>
    """
  end

  attr :diagnostics, :list, default: []

  defp diagnostics_list(%{diagnostics: []} = assigns) do
    ~H"""
    <p class="text-sm text-base-content/60">No warnings or unsupported definitions.</p>
    """
  end

  defp diagnostics_list(assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Notices</p>
      <ul class="space-y-1 text-sm" id="telemetry-decom-diagnostics">
        <li
          :for={d <- Enum.take(@diagnostics, 20)}
          class="flex items-start gap-2"
        >
          <.status_dot status={diagnostic_dot(d.severity)} size={:sm} class="mt-1.5" />
          <span>
            <span class="font-mono text-xs text-base-content/60">{d.code}</span>
            <span class="ml-1">{d.message}</span>
          </span>
        </li>
      </ul>
      <p :if={length(@diagnostics) > 20} class="text-xs text-base-content/60 mt-2">
        {length(@diagnostics) - 20} more omitted.
      </p>
    </div>
    """
  end

  attr :config, :any, default: nil

  defp actions_card(%{config: nil} = assigns), do: ~H""

  defp actions_card(assigns) do
    ~H"""
    <div class="card bg-base-200" id="telemetry-decom-actions-card">
      <div class="card-body p-6 space-y-3">
        <p class="hud-label">Apply</p>
        <p class="text-sm text-base-content/60">
          Applies all enabled Telemetry Decom spacecraft configurations for this mission, including this one.
        </p>
        <div class="flex gap-2">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="enable"
            id="telemetry-decom-enable-button"
          >
            Apply Mission Changes
          </button>
          <button
            :if={@config.enabled}
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click="disable"
            id="telemetry-decom-disable-button"
            data-confirm="Disable Telemetry Decom for this spacecraft?"
          >
            Disable
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp assign_config_form(socket, params) when is_map(params) do
    assign(socket, :config_form, to_form(params, as: "config"))
  end

  defp assign_config_form(socket, params) when is_list(params) do
    assign_config_form(socket, Map.new(params, fn {k, v} -> {to_string(k), v} end))
  end

  defp defaults_for(nil, revisions) do
    %{
      "catalog_revision_id" => first_option_value(revisions),
      "handled_apids" => ""
    }
  end

  defp defaults_for(config, _revisions) do
    %{
      "catalog_revision_id" => config.catalog_revision_id,
      "handled_apids" => APIDSelection.format(config.handled_apids)
    }
  end

  defp first_option_value([]), do: nil
  defp first_option_value([{_, value} | _]), do: value

  defp list_telemetry_revisions(organization_id, mission_id) do
    Catalog.list_revisions(organization_id, mission_id)
    |> Enum.filter(&(&1.telemetry_snapshot_id != nil))
    |> Enum.map(fn revision ->
      {"#{revision.revision_label} (##{revision.revision_number})", revision.catalog_revision_id}
    end)
  end

  defp preview_for(_organization_id, _mission_id, nil), do: nil

  defp preview_for(organization_id, mission_id, config) do
    case TelemetryDecom.preview(organization_id, mission_id, config) do
      {:ok, preview} -> Map.put(preview, :config, config)
      {:error, _reason} -> nil
    end
  end

  defp fetch_active_binding_set_summary(mission_id) do
    case Cadence.fetch_active_binding_set_activation(mission_id) do
      {:ok, activation} ->
        %{
          binding_set_id: activation.binding_set_id,
          binding_set_version: activation.binding_set_version
        }

      {:error, _} ->
        nil
    end
  end

  defp dot_status(:applied), do: :nominal
  defp dot_status(:configured), do: :info
  defp dot_status(:outdated), do: :warning
  defp dot_status(:disabled), do: :offline
  defp dot_status(:not_configured), do: :offline

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
      "This spacecraft is excluded from Telemetry Decom. Apply mission changes to publish the disabled state."

  defp status_description(:not_configured),
    do: "Choose a catalog revision and handled APIDs, then apply mission changes."

  defp diagnostic_dot(:error), do: :critical
  defp diagnostic_dot(:warning), do: :warning
  defp diagnostic_dot(_), do: :info

  defp format_apids(apids), do: APIDSelection.format(apids)

  defp humanize_error({:missing_attr, attr}), do: "missing #{attr}"
  defp humanize_error(:handled_apids_required), do: "handled APIDs are required"
  defp humanize_error(:no_enabled_configs), do: "no enabled spacecraft configurations"
  defp humanize_error({:invalid_apid_token, token}), do: "invalid APID token #{inspect(token)}"
  defp humanize_error({:invalid_apid_range, token}), do: "invalid APID range #{inspect(token)}"

  defp humanize_error({:handled_apids_not_in_revision, apids}),
    do: "APIDs not found in this revision: #{format_apids(apids)}"

  defp humanize_error(:spacecraft_runtime_scope_ambiguous),
    do: "spacecraft runtime scope is ambiguous"

  defp humanize_error(%Ecto.Changeset{} = changeset),
    do: changeset |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end) |> inspect()

  defp humanize_error(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp humanize_error(other), do: inspect(other)
end
