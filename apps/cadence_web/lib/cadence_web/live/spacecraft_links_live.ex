defmodule CadenceWeb.SpacecraftLinksLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents,
    only: [display_name: 2, human_atom: 1, profile_ref_display_label: 4, status_badge: 1]

  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    runtime_identity =
      SpacecraftCommsReadiness.runtime_identity(
        scope.organization_id,
        mission.mission_id,
        spacecraft
      )

    link_rows = link_rows(scope.organization_id, mission.mission_id, runtime_identity)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Link Assignments")
     |> assign(:nav_item, :spacecraft)
     |> assign_link_state(runtime_identity, link_rows)}
  end

  @impl true
  def handle_event("assign_link", %{"path-template-id" => path_template_id}, socket) do
    %{
      current_scope: scope,
      current_mission: mission,
      current_spacecraft: spacecraft,
      runtime_identity: runtime_identity
    } = socket.assigns

    with {:ok, _runtime_identity} <- require_runtime_identity(runtime_identity),
         {:ok, path_template} <-
           Cadence.fetch_path_template(
             scope.organization_id,
             mission.mission_id,
             path_template_id
           ),
         {:ok, %{applied_count: applied_count}} <-
           Cadence.apply_link_template(
             scope.organization_id,
             mission.mission_id,
             path_template,
             [spacecraft],
             assignment_params(path_template, spacecraft)
           ),
         :ok <- validate_applied_count(applied_count) do
      runtime_identity =
        SpacecraftCommsReadiness.runtime_identity(
          scope.organization_id,
          mission.mission_id,
          spacecraft
        )

      link_rows = link_rows(scope.organization_id, mission.mission_id, runtime_identity)

      {:noreply,
       socket
       |> put_flash(:info, "Mission link assigned to #{spacecraft.display_name}.")
       |> assign_link_state(runtime_identity, link_rows)}
    else
      {:error, :runtime_identity_missing} ->
        {:noreply, put_flash(socket, :error, "Create a runtime identity before assigning links.")}

      {:error, :link_assignment_not_applied} ->
        {:noreply,
         put_flash(socket, :error, "Link was not assigned. Review existing assignments.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not assign link: #{inspect(reason)}")}
    end
  end

  def handle_event("unassign_link", %{"link-assignment-id" => link_assignment_id}, socket) do
    %{
      current_scope: scope,
      current_mission: mission,
      current_spacecraft: spacecraft
    } = socket.assigns

    case Cadence.delete_link_assignment(
           scope.organization_id,
           mission.mission_id,
           link_assignment_id,
           %{"unassigned_from_ui" => true}
         ) do
      {:ok, _assignment} ->
        runtime_identity =
          SpacecraftCommsReadiness.runtime_identity(
            scope.organization_id,
            mission.mission_id,
            spacecraft
          )

        link_rows = link_rows(scope.organization_id, mission.mission_id, runtime_identity)

        {:noreply,
         socket
         |> put_flash(:info, "Mission link unassigned from #{spacecraft.display_name}.")
         |> assign_link_state(runtime_identity, link_rows)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not unassign link: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-links-page" class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
            }
            class="text-sm text-primary hover:underline"
          >
            &larr; Readiness
          </.link>
          <p class="hud-label mt-4 mb-2">Link Assignments</p>
          <h1 class="text-2xl font-bold text-base-content">
            {@current_spacecraft.display_name}
          </h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            Mission Network owns shared links. This page shows which mission link templates
            are available, assigned, or already used by another runtime identity.
          </p>
        </div>
        <.link
          navigate={assign_link_path(@current_mission.mission_id, @current_spacecraft)}
          class="btn btn-primary btn-sm"
          id="spacecraft-assign-link"
        >
          New Mission Link
        </.link>
      </div>

      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Runtime Identity</p>
              <h2 class="text-lg font-semibold">{runtime_identity_label(@runtime_identity)}</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Link templates attach to runtime identity so shared mission links can route
                bytes to spacecraft-owned interpretation.
              </p>
            </div>
            <.status_badge status={if @runtime_identity, do: :ready, else: :attention} />
          </div>
        </div>
      </section>

      <section class="card bg-base-200 border border-base-300">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Mission Link Templates</p>
              <h2 class="text-lg font-semibold">
                {@assigned_count} assigned / {length(@link_rows)} mission templates
              </h2>
              <p class="mt-1 text-sm text-base-content/60">
                Mission link templates are shown with their assignment state for this spacecraft.
              </p>
            </div>
            <.status_badge status={if @assigned_count == 0, do: :attention, else: :ready} />
          </div>

          <%= cond do %>
            <% is_nil(@runtime_identity) -> %>
              <div
                id="spacecraft-links-runtime-identity-empty"
                class="mt-6 rounded border border-base-300 bg-base-100/40 p-5 text-sm text-base-content/60"
              >
                Create or sync runtime identity before assigning mission links.
                <.link
                  navigate={
                    ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
                  }
                  class="text-primary hover:underline"
                >
                  Edit identity.
                </.link>
              </div>
            <% @link_rows == [] -> %>
              <div
                id="spacecraft-links-empty"
                class="mt-6 rounded border border-base-300 bg-base-100/40 p-5 text-sm text-base-content/60"
              >
                No mission link templates exist yet.
                <.link
                  navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates/new"}
                  class="text-primary hover:underline"
                >
                  Create a mission link template.
                </.link>
              </div>
            <% true -> %>
              <div class="mt-6 overflow-x-auto">
                <table id="spacecraft-link-assignments-table" class="table">
                  <thead>
                    <tr>
                      <th class="hud-label">Link Template</th>
                      <th class="hud-label">Assignment</th>
                      <th class="hud-label">Direction</th>
                      <th class="hud-label">Role</th>
                      <th class="hud-label">Providers</th>
                      <th class="hud-label">Protocol Behaviors</th>
                      <th class="hud-label text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @link_rows}>
                      <td>
                        <div class="font-medium">{display_name(row.template, :path_template_id)}</div>
                        <div class="font-mono text-xs text-base-content/50">
                          {row.template.path_template_id} · v{row.template.version}
                        </div>
                      </td>
                      <td>
                        <.status_badge status={row.status} label={row.label} />
                        <div :if={row.detail} class="mt-1 font-mono text-xs text-base-content/50">
                          {row.detail}
                        </div>
                      </td>
                      <td><.status_badge status={:info} label={human_atom(row.template.direction)} /></td>
                      <td class="text-sm">{human_atom(row.template.selection_role)}</td>
                      <td class="font-mono text-xs">
                        <%= if row.template.provider_profile_refs == [] do %>
                          <span class="text-base-content/40">None</span>
                        <% else %>
                          <div :for={label <- row.provider_labels}>
                            {label}
                          </div>
                        <% end %>
                      </td>
                      <td class="font-mono text-xs">
                        <%= if row.template.transport_profile_refs == [] do %>
                          <span class="text-base-content/40">None</span>
                        <% else %>
                          <div :for={label <- row.protocol_behavior_labels}>
                            {label}
                          </div>
                        <% end %>
                      </td>
                      <td class="text-right">
                        <.link
                          navigate={
                            ~p"/missions/#{@current_mission.mission_id}/comms/link-templates/#{row.template.path_template_id}"
                          }
                          class="btn btn-ghost btn-xs"
                        >
                          View
                        </.link>
                        <button
                          :if={row.assignment == :available}
                          id={"assign-link-#{row.template.path_template_id}"}
                          type="button"
                          phx-click="assign_link"
                          phx-value-path-template-id={row.template.path_template_id}
                          class="btn btn-ghost btn-xs"
                        >
                          Assign
                        </button>
                        <button
                          :if={row.assignment == :assigned}
                          id={"unassign-link-#{row.link_assignment.link_assignment_id}"}
                          type="button"
                          phx-click="unassign_link"
                          phx-value-link-assignment-id={row.link_assignment.link_assignment_id}
                          class="btn btn-ghost btn-xs"
                          data-confirm="Unassign this mission link from the spacecraft?"
                        >
                          Unassign
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  defp assign_link_state(socket, runtime_identity, link_rows) do
    socket
    |> assign(:runtime_identity, runtime_identity)
    |> assign(:link_rows, link_rows)
    |> assign(:assigned_count, assigned_count(link_rows))
  end

  defp require_runtime_identity(nil), do: {:error, :runtime_identity_missing}
  defp require_runtime_identity(runtime_identity), do: {:ok, runtime_identity}

  defp link_rows(_organization_id, _mission_id, nil), do: []

  defp link_rows(organization_id, mission_id, runtime_identity) do
    provider_profiles =
      organization_id
      |> Cadence.list_provider_profiles(mission_id)
      |> Map.new(&{&1.provider_profile_id, &1})

    transport_profiles =
      organization_id
      |> Cadence.list_transport_profiles(mission_id)
      |> Map.new(&{&1.transport_profile_id, &1})

    source_endpoints =
      organization_id
      |> Cadence.list_source_endpoints(mission_id)
      |> Map.new(&{&1.source_endpoint_id, &1})

    link_assignments = Cadence.list_link_assignments(organization_id, mission_id)

    organization_id
    |> Cadence.list_path_templates(mission_id)
    |> Enum.map(
      &link_row(
        &1,
        runtime_identity,
        link_assignments,
        provider_profiles,
        transport_profiles,
        source_endpoints
      )
    )
  end

  defp link_row(
         template,
         runtime_identity,
         link_assignments,
         provider_profiles,
         transport_profiles,
         source_endpoints
       ) do
    link_assignment =
      Enum.find(link_assignments, fn assignment ->
        assignment.path_template_id == template.path_template_id and
          assignment.source_endpoint_ref == runtime_identity.source_endpoint_id
      end)

    assignment =
      cond do
        link_assignment -> :assigned
        is_nil(template.source_endpoint_ref) -> :available
        true -> :legacy_direct
      end

    %{
      template: template,
      link_assignment: link_assignment,
      assignment: assignment,
      status: assignment_status(assignment),
      label: assignment_label(assignment),
      detail: assignment_detail(template, link_assignment, assignment, source_endpoints),
      provider_labels:
        profile_labels(
          template.provider_profile_refs,
          provider_profiles,
          "provider_profile_id",
          :provider_profile_id
        ),
      protocol_behavior_labels:
        profile_labels(
          template.transport_profile_refs,
          transport_profiles,
          "transport_profile_id",
          :transport_profile_id
        )
    }
  end

  defp profile_labels(refs, profiles_by_id, id_key, fallback_field) do
    Enum.map(refs, fn ref ->
      profile_ref_display_label(ref, id_key, profiles_by_id, fallback_field)
    end)
  end

  defp assigned_count(link_rows),
    do: Enum.count(link_rows, &(&1.assignment == :assigned))

  defp assignment_status(:assigned), do: :ready
  defp assignment_status(:available), do: :info
  defp assignment_status(:legacy_direct), do: :attention

  defp assignment_label(:assigned), do: "Assigned"
  defp assignment_label(:available), do: "Available"
  defp assignment_label(:legacy_direct), do: "Legacy direct identity"

  defp assignment_detail(_template, link_assignment, :assigned, _source_endpoints) do
    link_assignment.provider_path_ref
  end

  defp assignment_detail(_template, _link_assignment, :available, _source_endpoints), do: nil

  defp assignment_detail(template, _link_assignment, :legacy_direct, source_endpoints) do
    source_endpoint =
      Map.get(source_endpoints, template.source_endpoint_ref)

    label =
      case source_endpoint do
        nil -> template.source_endpoint_ref
        source_endpoint -> display_name(source_endpoint, :source_endpoint_id)
      end

    "Read-only legacy reference: #{label}"
  end

  defp runtime_identity_label(nil), do: "Not created"
  defp runtime_identity_label(runtime_identity), do: runtime_identity.source_endpoint_id

  defp assign_link_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/comms/link-templates/new?spacecraft_id=#{spacecraft.spacecraft_id}"
  end

  defp assignment_params(path_template, spacecraft) do
    direction = Atom.to_string(path_template.direction)

    %{
      "provider_path_ref_pattern" =>
        "#{spacecraft.spacecraft_id}-#{path_template.path_template_id}-#{direction}",
      "display_name_pattern" => "{spacecraft_name} {direction}"
    }
  end

  defp validate_applied_count(count) when count > 0, do: :ok
  defp validate_applied_count(_count), do: {:error, :link_assignment_not_applied}
end
