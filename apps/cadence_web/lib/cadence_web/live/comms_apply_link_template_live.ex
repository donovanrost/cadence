defmodule CadenceWeb.CommsApplyLinkTemplateLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    resources = load_resources(scope.organization_id, mission.mission_id)
    link_template_options = link_template_options(resources)
    form_params = default_form_params(resources)
    preview = preview_rows(resources, form_params)

    {:ok,
     socket
     |> assign(:page_title, "Apply Link Template")
     |> assign(:nav_item, :comms)
     |> assign(:resources, resources)
     |> assign(:link_template_options, link_template_options)
     |> assign(:template_available?, link_template_options != [])
     |> assign(:last_result, nil)
     |> assign(:selected_spacecraft_ids, MapSet.new())
     |> assign(:form_params, form_params)
     |> assign(:form, to_form(form_params, as: :link_application))
     |> assign_preview_counts(preview, form_params, MapSet.new())
     |> stream(:link_application_rows, preview.rows)}
  end

  @impl true
  def handle_event("validate", %{"link_application" => params}, socket) do
    preview = preview_rows(socket.assigns.resources, params)

    {:noreply,
     socket
     |> assign(:form_params, params)
     |> assign(:form, to_form(params, as: :link_application))
     |> assign_preview_counts(preview, params, socket.assigns.selected_spacecraft_ids)
     |> stream(:link_application_rows, preview.rows, reset: true)}
  end

  @impl true
  def handle_event("toggle_spacecraft", %{"spacecraft-id" => spacecraft_id}, socket) do
    selected_spacecraft_ids =
      toggle_selected(socket.assigns.selected_spacecraft_ids, spacecraft_id)

    preview = preview_rows(socket.assigns.resources, socket.assigns.form_params)

    {:noreply,
     socket
     |> assign(:selected_spacecraft_ids, selected_spacecraft_ids)
     |> assign_preview_counts(preview, socket.assigns.form_params, selected_spacecraft_ids)}
  end

  @impl true
  def handle_event("select_matching_spacecraft", _params, socket) do
    preview = preview_rows(socket.assigns.resources, socket.assigns.form_params)

    selected_spacecraft_ids =
      preview.rows
      |> Enum.filter(&(&1.kind == :ready))
      |> MapSet.new(& &1.spacecraft.spacecraft_id)

    {:noreply,
     socket
     |> assign(:selected_spacecraft_ids, selected_spacecraft_ids)
     |> assign_preview_counts(preview, socket.assigns.form_params, selected_spacecraft_ids)}
  end

  @impl true
  def handle_event("clear_selected_spacecraft", _params, socket) do
    preview = preview_rows(socket.assigns.resources, socket.assigns.form_params)
    selected_spacecraft_ids = MapSet.new()

    {:noreply,
     socket
     |> assign(:selected_spacecraft_ids, selected_spacecraft_ids)
     |> assign_preview_counts(preview, socket.assigns.form_params, selected_spacecraft_ids)}
  end

  @impl true
  def handle_event("apply", %{"link_application" => params}, socket) do
    %{current_scope: scope, current_mission: mission, resources: resources} = socket.assigns

    case fetch_path_template(resources, params["path_template_id"]) do
      {:ok, source_template} ->
        preview = preview_rows(resources, params)

        rows =
          target_rows(preview.rows, params["target_mode"], socket.assigns.selected_spacecraft_ids)

        {:ok, result} =
          Cadence.apply_link_template(
            scope.organization_id,
            mission.mission_id,
            source_template,
            Enum.map(rows, & &1.spacecraft),
            params
          )

        refreshed_resources = load_resources(scope.organization_id, mission.mission_id)
        refreshed_preview = preview_rows(refreshed_resources, params)

        {:noreply,
         socket
         |> put_flash(:info, result_flash(result))
         |> assign(:resources, refreshed_resources)
         |> assign(:last_result, result)
         |> assign(:form_params, params)
         |> assign_preview_counts(
           refreshed_preview,
           params,
           socket.assigns.selected_spacecraft_ids
         )
         |> stream(:link_application_rows, result.rows, reset: true)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-apply-link-template-page" class="space-y-6">
      <.comms_header current_mission={@current_mission} active={:overview} />

      <div class="max-w-4xl">
        <.link navigate={~p"/missions/#{@current_mission.mission_id}/comms"} class="text-sm text-primary hover:underline">
          &larr; Comms readiness
        </.link>
        <h1 class="mt-1 text-2xl font-bold text-base-content">Apply Link Template</h1>
        <p class="mt-1 max-w-3xl text-sm text-base-content/60">
          Select a reusable mission link template, preview which spacecraft need assignments,
          then apply spacecraft-specific link instances behind the scenes.
        </p>
      </div>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,32rem)_1fr]">
        <section class="card bg-base-200 border border-base-300">
          <div class="card-body p-6">
            <p class="hud-label mb-2">Template Application</p>
            <.form
              for={@form}
              id="link-application-form"
              phx-change="validate"
              phx-submit="apply"
              class="space-y-4"
            >
              <.input
                field={@form[:path_template_id]}
                type="select"
                label="Link Template"
                placeholder="Select a link template"
                options={@link_template_options}
                required
              />
              <div
                :if={!@template_available?}
                id="link-application-no-template"
                class="rounded border border-warning/30 bg-warning/10 p-4 text-sm text-warning"
              >
                Create an unassigned provider-backed Link Template before applying it to spacecraft.
              </div>
              <.input
                field={@form[:target_mode]}
                type="select"
                label="Apply Scope"
                options={[
                  {"All matching filter", "matching"},
                  {"Selected spacecraft", "selected"}
                ]}
              />
              <.input
                field={@form[:provider_path_ref_pattern]}
                type="text"
                label="Provider Path Ref Pattern"
                required
              />
              <.input
                field={@form[:display_name_pattern]}
                type="text"
                label="Path Display Name Pattern"
                required
              />
              <.input
                field={@form[:spacecraft_query]}
                type="text"
                label="Spacecraft Filter"
              />

              <div class="rounded border border-base-300 bg-base-100/40 p-4 text-xs text-base-content/60">
                Tokens: <span class="font-mono">{"{spacecraft_id}"}</span>,
                <span class="font-mono">{"{spacecraft_name}"}</span>,
                <span class="font-mono">{"{scid}"}</span>,
                <span class="font-mono">{"{direction}"}</span>.
              </div>

              <button
                id="link-application-apply-button"
                type="submit"
                class="btn btn-primary"
                disabled={@apply_target_count == 0 or @link_template_options == []}
              >
                Apply to {@apply_target_count} Spacecraft
              </button>
            </.form>
          </div>
        </section>

        <section class="space-y-4">
          <section
            :if={@last_result}
            id="link-application-result-summary"
            class="rounded border border-base-300 bg-base-200 p-4"
          >
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label mb-2">Application Result</p>
                <p class="text-sm text-base-content/60">
                  Cadence applied what it could and reports every skipped or failed row below.
                </p>
              </div>
              <.status_badge status={if @last_result.failed_count == 0, do: :ready, else: :warning} />
            </div>
            <div class="mt-4 grid gap-3 md:grid-cols-3">
              <.application_count_card id="link-application-applied-count" label="Applied" value={@last_result.applied_count} status={:ready} />
              <.application_count_card id="link-application-skipped-count" label="Skipped" value={@last_result.skipped_count} status={:info} />
              <.application_count_card id="link-application-failed-count" label="Failed" value={@last_result.failed_count} status={if @last_result.failed_count == 0, do: :ready, else: :missing} />
            </div>
          </section>

          <div class="grid gap-3 md:grid-cols-3">
            <.application_count_card id="link-application-ready-count" label="Ready to Apply" value={@ready_count} status={:ready} />
            <.application_count_card id="link-application-missing-scid-count" label="Missing SCID" value={@missing_scid_count} status={:missing} />
            <.application_count_card id="link-application-existing-count" label="Already Assigned" value={@already_configured_count} status={:info} />
          </div>

          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-6">
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="hud-label mb-2">Preview</p>
                  <h2 class="font-semibold">Constellation link assignment plan</h2>
                  <p class="mt-1 text-xs text-base-content/50">
                    {@selected_count} selected, {@selected_ready_count} ready.
                  </p>
                </div>
                <div class="flex flex-wrap items-center justify-end gap-2">
                  <button
                    id="link-application-select-matching"
                    type="button"
                    phx-click="select_matching_spacecraft"
                    class="btn btn-ghost btn-xs"
                  >
                    Select matching
                  </button>
                  <button
                    id="link-application-clear-selected"
                    type="button"
                    phx-click="clear_selected_spacecraft"
                    class="btn btn-ghost btn-xs"
                  >
                    Clear
                  </button>
                  <.status_badge status={if @ready_count == 0, do: :warning, else: :ready} />
                </div>
              </div>

              <div id="link-application-preview" phx-update="stream" class="mt-5 space-y-2">
                <div id="link-application-preview-empty" class="hidden only:block rounded border border-base-300 bg-base-100/40 p-4 text-sm text-base-content/60">
                  No spacecraft are available for preview.
                </div>
                <div
                  :for={{id, row} <- @streams.link_application_rows}
                  id={id}
                  class="grid gap-3 rounded border border-base-300 bg-base-100/40 p-4 md:grid-cols-[auto_1fr_auto]"
                >
                  <label class="flex items-start pt-1" for={"select-link-application-#{row.spacecraft.spacecraft_id}"}>
                    <input
                      id={"select-link-application-#{row.spacecraft.spacecraft_id}"}
                      type="checkbox"
                      class="checkbox checkbox-sm"
                      phx-click="toggle_spacecraft"
                      phx-value-spacecraft-id={row.spacecraft.spacecraft_id}
                      checked={MapSet.member?(@selected_spacecraft_ids, row.spacecraft.spacecraft_id)}
                    />
                  </label>
                  <div>
                    <p class="font-medium">{row.spacecraft.display_name}</p>
                    <p class="font-mono text-xs text-base-content/50">
                      {row.spacecraft.spacecraft_id} · SCID {format_scid(row.spacecraft.scid)}
                    </p>
                    <p class="mt-1 text-xs text-base-content/60">{row.detail}</p>
                  </div>
                  <div class="md:text-right">
                    <.status_badge status={row.status} label={row.label} />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :status, :atom, required: true

  defp application_count_card(assigns) do
    ~H"""
    <div id={@id} class="rounded border border-base-300 bg-base-200 p-4">
      <p class="hud-label mb-2">{@label}</p>
      <p class="font-mono text-3xl font-bold">{@value}</p>
      <div class="mt-3">
        <.status_badge status={@status} />
      </div>
    </div>
    """
  end

  defp load_resources(organization_id, mission_id) do
    spacecraft = Cadence.list_spacecraft(organization_id, mission_id)
    source_endpoints = Cadence.list_source_endpoints(organization_id, mission_id)
    path_templates = Cadence.list_path_templates(organization_id, mission_id)
    link_assignments = Cadence.list_link_assignments(organization_id, mission_id)

    %{
      spacecraft: spacecraft,
      source_endpoints: source_endpoints,
      path_templates: path_templates,
      link_assignments: link_assignments
    }
  end

  defp default_form_params(resources) do
    %{
      "path_template_id" => first_link_template_id(resources),
      "target_mode" => "matching",
      "provider_path_ref_pattern" => "{spacecraft_id}-{direction}",
      "display_name_pattern" => "{spacecraft_name} {direction}",
      "spacecraft_query" => ""
    }
  end

  defp link_template_options(resources) do
    resources
    |> applicable_link_templates()
    |> Enum.map(fn template ->
      label =
        [
          "#{display_name(template, :path_template_id)} v#{template.version}",
          human_atom(template.direction),
          human_atom(template.selection_role)
        ]
        |> Enum.join(" · ")

      {label, template.path_template_id}
    end)
  end

  defp preview_rows(resources, params) do
    source_template = selected_path_template(resources, params["path_template_id"])
    spacecraft = filter_spacecraft(resources.spacecraft, params["spacecraft_query"])

    rows =
      Enum.map(spacecraft, fn spacecraft ->
        preview_row(spacecraft, resources, source_template)
      end)

    %{
      rows: rows,
      ready_spacecraft: rows |> Enum.filter(&(&1.kind == :ready)) |> Enum.map(& &1.spacecraft),
      ready_count: Enum.count(rows, &(&1.kind == :ready)),
      missing_scid_count: Enum.count(rows, &(&1.kind == :missing_scid)),
      already_configured_count: Enum.count(rows, &(&1.kind == :already_configured))
    }
  end

  defp preview_row(%{scid: nil} = spacecraft, _resources, _source_template) do
    %{
      id: spacecraft.spacecraft_id,
      spacecraft: spacecraft,
      kind: :missing_scid,
      status: :missing,
      label: "Missing SCID",
      detail: "Set SCID before Cadence can generate a spacecraft-specific runtime identity."
    }
  end

  defp preview_row(spacecraft, _resources, nil) do
    %{
      id: spacecraft.spacecraft_id,
      spacecraft: spacecraft,
      kind: :missing_template,
      status: :warning,
      label: "Select template",
      detail: "Select a mission link template before Cadence can preview assignments."
    }
  end

  defp preview_row(spacecraft, resources, source_template) do
    endpoint_refs = endpoint_refs_for_spacecraft(spacecraft, resources.source_endpoints)
    direction = Atom.to_string(source_template.direction)

    if assigned_path_exists?(
         endpoint_refs,
         resources.path_templates,
         resources.link_assignments,
         source_template
       ) do
      %{
        id: spacecraft.spacecraft_id,
        spacecraft: spacecraft,
        kind: :already_configured,
        status: :info,
        label: "Already assigned",
        detail:
          "#{String.upcase(direction)} #{human_atom(source_template.selection_role)} link already exists."
      }
    else
      %{
        id: spacecraft.spacecraft_id,
        spacecraft: spacecraft,
        kind: :ready,
        status: :ready,
        label: "Will assign",
        detail:
          "Managed runtime identity will be synced and a #{human_atom(source_template.selection_role)} #{direction} link will be assigned."
      }
    end
  end

  defp endpoint_refs_for_spacecraft(spacecraft, source_endpoints) do
    managed_id = SpacecraftCommsReadiness.managed_source_endpoint_id(spacecraft.spacecraft_id)

    endpoint_refs =
      Enum.flat_map(source_endpoints, fn endpoint ->
        if endpoint_matches_spacecraft?(endpoint, spacecraft) do
          [endpoint.source_endpoint_id]
        else
          []
        end
      end)

    Enum.uniq([managed_id | endpoint_refs])
  end

  defp endpoint_matches_spacecraft?(endpoint, spacecraft) do
    endpoint.spacecraft_id == spacecraft.spacecraft_id or
      (not is_nil(spacecraft.scid) and endpoint.scid == spacecraft.scid)
  end

  defp assigned_path_exists?(endpoint_refs, _path_templates, link_assignments, source_template) do
    Enum.any?(link_assignments, fn assignment ->
      assignment.source_endpoint_ref in endpoint_refs and
        assignment.direction == source_template.direction and
        assignment.selection_role == source_template.selection_role and
        assignment.provider_profile_refs != []
    end)
  end

  defp fetch_path_template(resources, path_template_id) do
    case selected_path_template(resources, path_template_id) do
      nil -> {:error, "Link template is required."}
      template -> {:ok, template}
    end
  end

  defp filter_spacecraft(spacecraft, query) do
    case normalize_text(query) do
      nil ->
        spacecraft

      query ->
        normalized_query = String.downcase(query)

        Enum.filter(spacecraft, fn spacecraft ->
          spacecraft
          |> spacecraft_search_text()
          |> String.contains?(normalized_query)
        end)
    end
  end

  defp spacecraft_search_text(spacecraft) do
    [
      spacecraft.spacecraft_id,
      spacecraft.display_name,
      if(spacecraft.scid, do: Integer.to_string(spacecraft.scid), else: nil)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp first_link_template_id(resources) do
    case applicable_link_templates(resources) do
      [template | _rest] -> template.path_template_id
      [] -> ""
    end
  end

  defp selected_path_template(_resources, nil), do: nil
  defp selected_path_template(_resources, ""), do: nil

  defp selected_path_template(resources, path_template_id) do
    resources
    |> applicable_link_templates()
    |> Enum.find(&(&1.path_template_id == path_template_id))
  end

  defp applicable_link_templates(resources) do
    Enum.filter(resources.path_templates, fn path_template ->
      path_template.provider_profile_refs != [] and is_nil(path_template.source_endpoint_ref)
    end)
  end

  defp result_flash(%{applied_count: applied, skipped_count: skipped, failed_count: 0}) do
    "Applied link template to #{applied} spacecraft; skipped #{skipped}."
  end

  defp result_flash(%{applied_count: applied, skipped_count: skipped, failed_count: failed}) do
    "Applied link template to #{applied} spacecraft; skipped #{skipped}; failed #{failed}."
  end

  defp assign_preview_counts(socket, preview, params, selected_spacecraft_ids) do
    target_rows = target_rows(preview.rows, params["target_mode"], selected_spacecraft_ids)
    selected_rows = target_rows(preview.rows, "selected", selected_spacecraft_ids)

    socket
    |> assign(:ready_count, preview.ready_count)
    |> assign(:target_mode, target_mode(params["target_mode"]))
    |> assign(:apply_target_count, Enum.count(target_rows, &(&1.kind == :ready)))
    |> assign(:selected_count, Enum.count(selected_rows))
    |> assign(:selected_ready_count, Enum.count(selected_rows, &(&1.kind == :ready)))
    |> assign(:missing_scid_count, preview.missing_scid_count)
    |> assign(:already_configured_count, preview.already_configured_count)
  end

  defp target_rows(rows, "selected", selected_spacecraft_ids) do
    Enum.filter(rows, &MapSet.member?(selected_spacecraft_ids, &1.spacecraft.spacecraft_id))
  end

  defp target_rows(rows, _target_mode, _selected_spacecraft_ids), do: rows

  defp target_mode("selected"), do: "selected"
  defp target_mode(_value), do: "matching"

  defp toggle_selected(selected_spacecraft_ids, spacecraft_id) do
    if MapSet.member?(selected_spacecraft_ids, spacecraft_id) do
      MapSet.delete(selected_spacecraft_ids, spacecraft_id)
    else
      MapSet.put(selected_spacecraft_ids, spacecraft_id)
    end
  end

  defp format_scid(nil), do: "not set"
  defp format_scid(scid), do: Integer.to_string(scid)
end
