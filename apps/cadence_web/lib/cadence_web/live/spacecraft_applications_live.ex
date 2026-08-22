defmodule CadenceWeb.SpacecraftApplicationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias CadenceWeb.{ApplicationInventory, ApplicationInventoryCard, ApplicationInventoryLifecycle}

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    type_binding = load_type_binding(scope.organization_id, mission.mission_id, spacecraft)
    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
    applications = application_rows(scope, type_binding, host_context)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Applications")
     |> assign(:nav_item, :spacecraft)
     |> assign(:type_binding, type_binding)
     |> assign(:application_host_context, host_context)
     |> assign(:applications_empty?, applications == [])
     |> stream_configure(:applications,
       dom_id: fn application ->
         ApplicationInventoryCard.dom_id(host_context, application.application_key)
       end
     )
     |> stream(:applications, applications)}
  end

  @impl true
  def handle_event("install_application", %{"key" => application_key}, socket) do
    %{current_scope: scope, type_binding: type_binding, application_host_context: host_context} =
      socket.assigns

    decision = install_decision(scope, type_binding, host_context, application_key)

    ApplicationInventoryLifecycle.install(
      socket,
      application_key,
      decision,
      &refresh_applications/1
    )
  end

  def handle_event("disable_application", %{"key" => application_key}, socket) do
    ApplicationInventoryLifecycle.disable(socket, application_key, &refresh_applications/1)
  end

  def handle_event("uninstall_application", %{"key" => application_key}, socket) do
    ApplicationInventoryLifecycle.uninstall(socket, application_key, &refresh_applications/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="spacecraft-applications-page" class="space-y-6">
      <.page_header
        title="Applications"
        subtitle="Install profile-declared product applications and open their host-rendered workspaces."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Applications", nil}
        ]}
      >
        <:actions>
          <.button
            variant={:ghost}
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/readiness"
            }
          >
            Readiness
          </.button>
        </:actions>
      </.page_header>

      <.card
        :if={is_nil(@type_binding)}
        id="spacecraft-applications-no-profile"
        title="Spacecraft Profile"
      >
        <h2 class="mt-2 text-base font-semibold">No profile selected</h2>
        <p class="mt-1 text-sm text-base-content/70">
          Select a Spacecraft Profile before installing profile-declared applications.
        </p>
        <.button
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/identity"
          }
          class="mt-5"
        >
          Select profile
        </.button>
      </.card>

      <.card :if={@type_binding} id="spacecraft-applications-profile">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label">Pinned Profile</p>
            <h2 class="mt-2 text-base font-semibold">
              {@type_binding.pinned.display_name}
              <span class="mc-value-small text-base-content/70">v{@type_binding.pinned.version}</span>
            </h2>
          </div>
          <.status_badge
            status={if(@type_binding.drift?, do: :attention, else: :ready)}
            label={if(@type_binding.drift?, do: "Profile drift", else: "Current")}
          />
        </div>
      </.card>

      <section
        :if={@type_binding || not @applications_empty?}
        id="spacecraft-applications-list"
        class="grid gap-4 lg:grid-cols-2"
        phx-update="stream"
      >
        <ApplicationInventoryCard.application_inventory_card
          :for={{dom_id, app} <- @streams.applications}
          id={dom_id}
          app={app}
          host_context={@application_host_context}
          manage_path={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/applications/#{app.application_key}"
          }
        />
      </section>
      </div>
    </Layouts.app>
    """
  end

  defp application_rows(scope, nil, host_context) do
    load_application_rows(scope, host_context, %{})
  end

  defp application_rows(
         scope,
         %{pinned: %{applications: applications}},
         %HostContext{} = host_context
       ) do
    load_application_rows(scope, host_context, applications)
  end

  defp load_application_rows(scope, host_context, applications) do
    case ApplicationInventory.declared(scope, host_context, applications) do
      {:ok, application_inventory} -> application_inventory
      {:error, _reason} -> []
    end
  end

  defp desired_application?(%{pinned: %{applications: applications}}, application_key),
    do: Map.has_key?(applications, application_key)

  defp desired_application?(_type_binding, _application_key), do: false

  defp install_allowed?(scope, type_binding, host_context, application_key) do
    desired_application?(type_binding, application_key) or
      retained_application?(scope, host_context, application_key)
  end

  defp install_decision(scope, type_binding, host_context, application_key) do
    if install_allowed?(scope, type_binding, host_context, application_key) do
      :allowed
    else
      {:denied, "Application is neither declared by this profile nor retained at this scope."}
    end
  end

  defp retained_application?(scope, host_context, application_key) do
    case ApplicationInstallations.fetch(scope, host_context, application_key) do
      {:ok, _installation} -> true
      {:error, _reason} -> false
    end
  end

  defp load_type_binding(_organization_id, _mission_id, %{spacecraft_type_id: nil}), do: nil

  defp load_type_binding(organization_id, mission_id, spacecraft) do
    pinned =
      Cadence.SpacecraftTypeStore.fetch_spacecraft_type_version(
        organization_id,
        mission_id,
        spacecraft.spacecraft_type_id,
        spacecraft.spacecraft_type_version
      )

    latest =
      Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
        organization_id,
        mission_id,
        spacecraft.spacecraft_type_id
      )

    case {pinned, latest} do
      {{:ok, pinned_type}, {:ok, latest_type}} ->
        %{
          pinned: pinned_type,
          latest_version: latest_type.version,
          drift?: latest_type.version > pinned_type.version
        }

      {{:ok, pinned_type}, _} ->
        %{pinned: pinned_type, latest_version: pinned_type.version, drift?: false}

      _ ->
        nil
    end
  end

  defp refresh_applications(socket) do
    applications =
      application_rows(
        socket.assigns.current_scope,
        socket.assigns.type_binding,
        socket.assigns.application_host_context
      )

    socket
    |> assign(:applications_empty?, applications == [])
    |> stream(:applications, applications, reset: true)
  end
end
