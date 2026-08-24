defmodule CadenceWeb.MissionApplicationsLive do
  @moduledoc "Mission-scoped inventory for registered product applications."

  use CadenceWeb, :live_view

  alias Cadence.Applications.{ActionConfirmation, HostContext, LifecycleActions}
  alias CadenceWeb.{ApplicationInventory, ApplicationInventoryCard, ApplicationInventoryLifecycle}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    host_context = HostContext.mission(socket.assigns.current_mission.mission_id)
    applications = application_rows(socket.assigns.current_scope, host_context)

    {:ok,
     socket
     |> assign(:page_title, "#{socket.assigns.current_mission.display_name} Applications")
     |> assign(:nav_item, :mission_applications)
     |> assign(:application_host_context, host_context)
     |> assign(
       :application_rows,
       application_rows_dto(applications, host_context, socket.assigns.current_mission.mission_id)
     )}
  end

  @impl true
  def handle_event("install_application", %{"key" => application_key}, socket) do
    ApplicationInventoryLifecycle.install(
      socket,
      application_key,
      :allowed,
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
      <div id="mission-applications-page" class="space-y-6">
        <.page_header
          title="Applications"
          subtitle="Install mission-scoped product capabilities and open their host-rendered workspaces."
          breadcrumbs={[
            {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
            {"Applications", nil}
          ]}
        />

        <.vue
          id="mission-applications-component"
          v-component="MissionApplications"
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

  defp application_rows(scope, host_context) do
    case ApplicationInventory.catalog(scope, host_context) do
      {:ok, applications} -> applications
      {:error, _reason} -> []
    end
  end

  defp refresh_applications(socket) do
    applications =
      application_rows(
        socket.assigns.current_scope,
        socket.assigns.application_host_context
      )

    assign(
      socket,
      :application_rows,
      application_rows_dto(
        applications,
        socket.assigns.application_host_context,
        socket.assigns.current_mission.mission_id
      )
    )
  end

  defp application_rows_dto(applications, host_context, mission_id) do
    Enum.map(applications, &application_row_dto(&1, host_context, mission_id))
  end

  defp application_row_dto(application, host_context, mission_id) do
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
      scope_label: "Mission Application",
      manage_path: ~p"/missions/#{mission_id}/applications/#{application.application_key}",
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
