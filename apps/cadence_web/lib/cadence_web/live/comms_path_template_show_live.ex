defmodule CadenceWeb.CommsPathTemplateShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(%{"path_template_id" => path_template_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_path_template(scope.organization_id, mission.mission_id, path_template_id) do
      {:ok, path_template} ->
        source_endpoints =
          Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)

        spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)

        link_assignments =
          Cadence.list_link_assignments(scope.organization_id, mission.mission_id)

        provider_profiles =
          Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

        transport_profiles =
          Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

        versions =
          Cadence.list_path_template_versions(
            scope.organization_id,
            mission.mission_id,
            path_template_id
          )

        provider_profiles_by_id =
          profile_versions_by_ref(
            provider_profiles,
            path_template.provider_profile_refs,
            "provider_profile_id",
            &Cadence.list_provider_profile_versions/3,
            scope.organization_id,
            mission.mission_id
          )

        transport_profiles_by_id =
          profile_versions_by_ref(
            transport_profiles,
            path_template.transport_profile_refs,
            "transport_profile_id",
            &Cadence.list_transport_profile_versions/3,
            scope.organization_id,
            mission.mission_id
          )

        {:ok,
         socket
         |> assign(:page_title, display_name(path_template, :path_id))
         |> assign(:nav_item, :comms_link_templates)
         |> assign(:path_template, path_template)
         |> assign(:versions, versions)
         |> assign(
           :coverage,
           coverage_summary(
             path_template,
             spacecraft,
             source_endpoints,
             link_assignments
           )
         )
         |> assign(
           :profile_ref_findings,
           CadenceWeb.CommsValidation.profile_ref_findings(
             path_template,
             provider_profiles_by_id,
             transport_profiles_by_id,
             mission.mission_id
           )
         )
         |> assign(
           :source_endpoints_by_id,
           Map.new(source_endpoints, &{&1.source_endpoint_id, &1})
         )
         |> assign(:provider_profiles_by_id, provider_profiles_by_id)
         |> assign(:transport_profiles_by_id, transport_profiles_by_id)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Path template not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/link-templates")}
    end
  end

  @impl true
  def handle_event("archive", _params, socket) do
    %{current_scope: scope, current_mission: mission, path_template: path_template} =
      socket.assigns

    case Cadence.delete_path_template(
           scope.organization_id,
           mission.mission_id,
           path_template.path_template_id,
           %{"archived_from_ui" => true}
         ) do
      {:ok, _path_template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Path template archived.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/link-templates")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-path-template-show-page" class="space-y-6">
      <.comms_header current_mission={@current_mission} active={:path_templates} />

      <div class="flex items-start justify-between gap-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates"}
            class="text-sm text-primary hover:underline"
          >
            &larr; Link Templates
          </.link>
          <h1 class="mt-1 text-2xl font-bold text-base-content">
            {display_name(@path_template, :path_id)}
          </h1>
          <p class="mt-1 font-mono text-xs text-base-content/50">
            {@path_template.path_template_id} · v{@path_template.version}
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <button
            id="archive-path-template-button"
            type="button"
            phx-click="archive"
            data-confirm="Archive this link template?"
            class="btn btn-error btn-outline btn-sm"
          >
            Archive
          </button>
          <.link
            id="new-path-template-version-link"
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/link-templates/#{@path_template.path_template_id}/new-version"
            }
            class="btn btn-primary btn-sm"
          >
            New Version
          </.link>
        </div>
      </div>

      <section
        :if={@profile_ref_findings != []}
        id="path-template-profile-version-findings"
        class="card bg-warning/10 border border-warning/30"
      >
        <div class="card-body p-5">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2 text-warning">Profile Version Drift</p>
              <h2 class="font-semibold">This path is pinned to older or missing profile versions.</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Create a new path version when you intentionally want operations to use the
                latest provider or protocol behavior versions.
              </p>
            </div>
            <.status_badge status={:warning} label={"#{Enum.count(@profile_ref_findings)} Findings"} />
          </div>

          <div class="mt-4 space-y-3">
            <div :for={finding <- @profile_ref_findings} class="rounded border border-base-300 bg-base-100/50 p-4">
              <h3 class="font-semibold">{finding.title}</h3>
              <p class="mt-1 text-sm text-base-content/60">{finding.body}</p>
            </div>
          </div>

          <.link
            id="path-template-version-drift-action"
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/link-templates/#{@path_template.path_template_id}/new-version"
            }
            class="btn btn-primary btn-sm mt-4"
          >
            Create new path version
          </.link>
        </div>
      </section>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <section class="card bg-base-200">
          <div class="card-body p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label mb-2">Reusable Template</p>
                <h2 class="text-lg font-semibold">
                  {source_endpoint_label(@path_template.source_endpoint_ref, @source_endpoints_by_id)}
                </h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Versioned mission link template. Spacecraft usage is tracked by explicit link
                  assignments.
                </p>
              </div>
              <.status_badge status={:info} label={human_atom(@path_template.direction)} />
            </div>

            <div class="mt-6 divide-y divide-base-300">
              <.path_detail label="Direction" value={human_atom(@path_template.direction)} />
              <.path_detail label="Selection role" value={human_atom(@path_template.selection_role)} />
              <.path_detail label="Provider path ref" value={@path_template.provider_path_ref || "Not set"} />
              <.path_detail
                label="Scope"
                value={source_endpoint_label(@path_template.source_endpoint_ref, @source_endpoints_by_id)}
              />
              <.path_detail label="Assigned spacecraft" value={Integer.to_string(@coverage.assigned_count)} />
              <.path_detail label="Available spacecraft" value={Integer.to_string(@coverage.available_count)} />
            </div>

            <div class="mt-6 grid gap-4 md:grid-cols-2">
              <.profile_ref_card
                title="Providers"
                refs={@path_template.provider_profile_refs}
                id_key="provider_profile_id"
                profiles_by_id={@provider_profiles_by_id}
              />
              <.profile_ref_card
                title="Protocol Behaviors"
                refs={@path_template.transport_profile_refs}
                id_key="transport_profile_id"
                profiles_by_id={@transport_profiles_by_id}
              />
            </div>

            <details class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
              <summary class="cursor-pointer hud-label">Raw Link Template</summary>
              <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(raw_path_template(@path_template), pretty: true)}</pre>
            </details>
          </div>
        </section>

        <aside class="space-y-4">
          <section id="path-template-coverage" class="card bg-base-200 border border-base-300">
            <div class="card-body p-5">
              <p class="hud-label mb-2">Coverage</p>
              <div class="grid grid-cols-2 gap-3">
                <.coverage_metric label="Assigned" value={@coverage.assigned_count} />
                <.coverage_metric label="Available" value={@coverage.available_count} />
              </div>

              <div class="mt-4 space-y-2">
                <div
                  :for={row <- @coverage.assigned_rows}
                  class="rounded border border-base-300 bg-base-100/40 p-3"
                >
                  <p class="text-sm font-medium">{row.spacecraft_label}</p>
                  <p class="font-mono text-xs text-base-content/50">{row.runtime_identity_label}</p>
                </div>
                <p
                  :if={@coverage.assigned_rows == []}
                  class="rounded border border-base-300 bg-base-100/40 p-3 text-sm text-base-content/60"
                >
                  No spacecraft assignments use this link yet.
                </p>
              </div>
            </div>
          </section>

          <section class="card bg-base-200 border border-base-300">
            <div class="card-body p-5">
              <p class="hud-label mb-2">Version History</p>
              <div id="path-template-versions" class="space-y-3">
                <div :for={version <- @versions} class="flex items-center justify-between border-b border-base-300 pb-2 last:border-b-0">
                  <span class="font-mono">v{version.version}</span>
                  <span class="text-xs text-base-content/60">
                    {version.lifecycle_state |> Atom.to_string() |> String.upcase()}
                  </span>
                </div>
              </div>
            </div>
          </section>
        </aside>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp path_detail(assigns) do
    ~H"""
    <div class="grid gap-2 py-3 sm:grid-cols-[12rem_1fr]">
      <div class="hud-label text-base-content/50">{@label}</div>
      <div class="text-sm text-base-content">{@value}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp coverage_metric(assigns) do
    ~H"""
    <div class="rounded border border-base-300 bg-base-100/40 p-3">
      <p class="hud-label mb-2">{@label}</p>
      <p class="font-mono text-2xl font-bold">{@value}</p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :refs, :list, required: true
  attr :id_key, :string, required: true
  attr :profiles_by_id, :map, required: true

  defp profile_ref_card(assigns) do
    ~H"""
    <div class="rounded border border-base-300 bg-base-100/40 p-4">
      <p class="hud-label mb-3">{@title}</p>
      <%= if @refs == [] do %>
        <p class="text-sm text-base-content/50">None</p>
      <% else %>
        <div :for={ref <- @refs} class="mb-2 last:mb-0">
          <p class="text-sm font-medium">{profile_ref_display(ref, @id_key, @profiles_by_id)}</p>
          <p class="font-mono text-xs text-base-content/50">{profile_ref_label(ref, @id_key)}</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp source_endpoint_label(nil, _source_endpoints_by_id), do: "Reusable mission template"

  defp source_endpoint_label(source_endpoint_ref, source_endpoints_by_id) do
    case Map.fetch(source_endpoints_by_id, source_endpoint_ref) do
      {:ok, endpoint} ->
        "Legacy direct identity: #{endpoint.display_name || endpoint.source_endpoint_id}"

      :error ->
        "Legacy direct identity: #{source_endpoint_ref} (missing)"
    end
  end

  defp profile_ref_display(ref, id_key, profiles_by_id) do
    profile_id = Map.get(ref, id_key)

    case Map.fetch(profiles_by_id, profile_id) do
      {:ok, {:archived, profile}} ->
        "#{display_name(profile, profile_fallback_field(id_key))} (archived)"

      {:ok, profile} ->
        display_name(profile, profile_fallback_field(id_key))

      :error ->
        "#{profile_id} (missing)"
    end
  end

  defp profile_fallback_field("provider_profile_id"), do: :provider_profile_id
  defp profile_fallback_field("transport_profile_id"), do: :transport_profile_id

  defp raw_path_template(path_template) do
    %{
      "path_template_id" => path_template.path_template_id,
      "path_id" => path_template.path_id,
      "version" => path_template.version,
      "direction" => Atom.to_string(path_template.direction),
      "selection_role" => Atom.to_string(path_template.selection_role),
      "source_endpoint_ref" => path_template.source_endpoint_ref,
      "provider_path_ref" => path_template.provider_path_ref,
      "provider_profile_refs" => path_template.provider_profile_refs,
      "transport_profile_refs" => path_template.transport_profile_refs,
      "metadata" => path_template.metadata
    }
  end

  defp coverage_summary(
         path_template,
         spacecraft,
         source_endpoints,
         link_assignments
       ) do
    source_endpoints_by_id = Map.new(source_endpoints, &{&1.source_endpoint_id, &1})
    spacecraft_by_id = Map.new(spacecraft, &{&1.spacecraft_id, &1})

    assigned_link_rows =
      link_assignments
      |> Enum.filter(&(&1.path_template_id == path_template.path_template_id))
      |> Enum.map(&assignment_row(&1, source_endpoints_by_id, spacecraft_by_id))

    %{
      assigned_count: Enum.count(assigned_link_rows),
      available_count:
        available_spacecraft_count(
          path_template,
          spacecraft,
          source_endpoints,
          link_assignments
        ),
      assigned_rows: assigned_link_rows
    }
  end

  defp assignment_row(assignment, source_endpoints_by_id, spacecraft_by_id) do
    endpoint = Map.get(source_endpoints_by_id, assignment.source_endpoint_ref)
    spacecraft = endpoint && Map.get(spacecraft_by_id, endpoint.spacecraft_id)

    %{
      spacecraft_label:
        (spacecraft && spacecraft.display_name) ||
          (endpoint && endpoint.display_name) ||
          assignment.source_endpoint_ref,
      runtime_identity_label:
        (endpoint && (endpoint.display_name || endpoint.source_endpoint_id)) ||
          assignment.source_endpoint_ref
    }
  end

  defp available_spacecraft_count(
         %{source_endpoint_ref: source_endpoint_ref},
         _spacecraft,
         _source_endpoints,
         _link_assignments
       )
       when not is_nil(source_endpoint_ref),
       do: 0

  defp available_spacecraft_count(
         path_template,
         spacecraft,
         source_endpoints,
         link_assignments
       ) do
    Enum.count(spacecraft, fn spacecraft ->
      spacecraft.scid != nil and
        not assigned_to_spacecraft?(
          spacecraft,
          path_template,
          source_endpoints,
          link_assignments
        )
    end)
  end

  defp assigned_to_spacecraft?(
         spacecraft,
         path_template,
         source_endpoints,
         link_assignments
       ) do
    endpoint_refs = endpoint_refs_for_spacecraft(spacecraft, source_endpoints)

    Enum.any?(link_assignments, fn assignment ->
      assignment.source_endpoint_ref in endpoint_refs and
        assignment.direction == path_template.direction and
        assignment.selection_role == path_template.selection_role and
        assignment.provider_profile_refs != []
    end)
  end

  defp endpoint_refs_for_spacecraft(spacecraft, source_endpoints) do
    managed_id = "spacecraft_runtime:" <> spacecraft.spacecraft_id

    endpoint_refs =
      Enum.flat_map(source_endpoints, fn endpoint ->
        if endpoint.spacecraft_id == spacecraft.spacecraft_id or endpoint.scid == spacecraft.scid do
          [endpoint.source_endpoint_id]
        else
          []
        end
      end)

    Enum.uniq([managed_id | endpoint_refs])
  end

  defp profile_versions_by_ref(
         active_profiles,
         refs,
         id_key,
         list_versions,
         organization_id,
         mission_id
       ) do
    active_profiles_by_id = profile_map(active_profiles, id_key)

    refs
    |> Enum.map(&Map.get(&1, id_key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce(active_profiles_by_id, fn profile_id, profiles_by_id ->
      maybe_put_referenced_profile(
        profiles_by_id,
        profile_id,
        list_versions.(organization_id, mission_id, profile_id)
      )
    end)
  end

  defp maybe_put_referenced_profile(profiles_by_id, profile_id, versions) do
    if Map.has_key?(profiles_by_id, profile_id) do
      profiles_by_id
    else
      put_referenced_profile(profiles_by_id, profile_id, versions)
    end
  end

  defp put_referenced_profile(profiles_by_id, profile_id, [
         %{lifecycle_state: :deleted} = latest_profile | _versions
       ]) do
    Map.put(profiles_by_id, profile_id, {:archived, latest_profile})
  end

  defp put_referenced_profile(profiles_by_id, profile_id, [latest_profile | _versions]) do
    Map.put(profiles_by_id, profile_id, latest_profile)
  end

  defp put_referenced_profile(profiles_by_id, _profile_id, []), do: profiles_by_id

  defp profile_map(profiles, "provider_profile_id") do
    Map.new(profiles, &{&1.provider_profile_id, &1})
  end

  defp profile_map(profiles, "transport_profile_id") do
    Map.new(profiles, &{&1.transport_profile_id, &1})
  end
end
