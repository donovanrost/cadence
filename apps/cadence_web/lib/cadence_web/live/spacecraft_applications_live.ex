defmodule CadenceWeb.SpacecraftApplicationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.{
    ActionConfirmation,
    ApplicationInstallations,
    HostContext,
    LifecycleActions
  }

  alias CadenceWeb.{ApplicationInventory, ApplicationInventoryCard, ApplicationInventoryLifecycle}
  alias Phoenix.LiveView.JS

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
     |> assign(
       :profile_card,
       profile_card_dto(type_binding, mission.mission_id, spacecraft.spacecraft_id)
     )
     |> assign(
       :application_rows,
       application_rows_dto(
         applications,
         host_context,
         mission.mission_id,
         spacecraft.spacecraft_id
       )
     )}
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

        <.vue
          id="spacecraft-applications-component"
          v-component="SpacecraftApplications"
          profile={@profile_card}
          applications={@application_rows}
          v-on:install={JS.push("install_application")}
          v-on:disable={JS.push("disable_application")}
          v-on:uninstall={JS.push("uninstall_application")}
          v-diff={false}
          v-ssr={false}
        />
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

    assign(
      socket,
      :application_rows,
      application_rows_dto(
        applications,
        socket.assigns.application_host_context,
        socket.assigns.current_mission.mission_id,
        socket.assigns.current_spacecraft.spacecraft_id
      )
    )
  end

  defp profile_card_dto(nil, mission_id, spacecraft_id) do
    %{
      kind: "missing",
      id: "spacecraft-applications-no-profile",
      label: "Spacecraft Profile",
      title: "No profile selected",
      description: "Select a Spacecraft Profile before installing profile-declared applications.",
      action: %{
        label: "Select profile",
        path: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/identity"
      }
    }
  end

  defp profile_card_dto(%{pinned: pinned, drift?: drift?}, _mission_id, _spacecraft_id) do
    %{
      kind: "pinned",
      id: "spacecraft-applications-profile",
      label: "Pinned Profile",
      display_name: pinned.display_name,
      version: pinned.version,
      status: %{
        tone: if(drift?, do: "attention", else: "ready"),
        label: if(drift?, do: "Profile drift", else: "Current")
      }
    }
  end

  defp application_rows_dto(applications, host_context, mission_id, spacecraft_id) do
    Enum.map(
      applications,
      &application_row_dto(&1, host_context, mission_id, spacecraft_id)
    )
  end

  defp application_row_dto(application, host_context, mission_id, spacecraft_id) do
    card_id = ApplicationInventoryCard.dom_id(host_context, application.application_key)

    %{
      id: card_id,
      application_key: application.application_key,
      application_version: application.application_version,
      display_name: application.display_name,
      description: application.description,
      lifecycle_state: atom_string(application.lifecycle_state),
      installable: application.installable?,
      manageable: application.manageable?,
      uninstallable: application.uninstallable?,
      scope_label: "Application",
      manage_path:
        ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/applications/#{application.application_key}",
      status: status_dto(application.status),
      install_action: install_action_dto(application, card_id),
      disable_action: if(application.manageable?, do: lifecycle_action_dto("disable", card_id)),
      uninstall_action:
        if(application.uninstallable?, do: lifecycle_action_dto("uninstall", card_id)),
      unavailable_message:
        if(application.installable?,
          do: nil,
          else: "This application is not available for installation in this deployment."
        )
    }
  end

  defp status_dto(status) do
    %{
      state: Atom.to_string(status.state),
      label: status.label,
      tone: Atom.to_string(status.tone),
      facts:
        Enum.map(status.facts, fn fact ->
          %{id: fact.id, label: fact.label, value: fact.value}
        end)
    }
  end

  defp install_action_dto(application, card_id) do
    if application.installable? and not application.manageable? do
      %{
        id: "install-#{card_id}",
        action_id: "install",
        label: install_label(application.lifecycle_state),
        variant: "primary",
        effect: "durable",
        execution: "immediate",
        confirmation: nil
      }
    end
  end

  defp lifecycle_action_dto(action_id, card_id) do
    {:ok, action} = LifecycleActions.fetch(action_id)

    %{
      id: "#{action_id}-#{card_id}",
      action_id: action.action_id,
      label: action.label,
      variant: Atom.to_string(action.button_variant),
      effect: Atom.to_string(action.effect),
      execution: Atom.to_string(action.execution),
      confirmation: confirmation_dto(action.confirmation)
    }
  end

  defp confirmation_dto(nil), do: nil

  defp confirmation_dto(%ActionConfirmation{} = confirmation) do
    %{
      title: confirmation.title,
      message: confirmation.message,
      confirm_label: confirmation.confirm_label,
      tone: Atom.to_string(confirmation.tone),
      prompt: ActionConfirmation.prompt(confirmation)
    }
  end

  defp install_label(:disabled), do: "Enable"
  defp install_label(:uninstalled), do: "Reinstall"
  defp install_label(:installed), do: "Upgrade"
  defp install_label(_lifecycle_state), do: "Install"

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
end
