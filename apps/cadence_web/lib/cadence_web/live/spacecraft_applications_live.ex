defmodule CadenceWeb.SpacecraftApplicationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.{
    ActionConfirmation,
    ApplicationInstallations,
    HostContext,
    LifecycleActions
  }

  alias CadenceWeb.{ApplicationHostCatalog, ApplicationInventory, ApplicationInventoryLifecycle}

  @impl true
  def mount(_params, _session, socket) do
    now = request_boundary_now()

    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    type_binding = load_type_binding(scope.organization_id, mission.mission_id, spacecraft)
    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
    applications = application_rows(scope, type_binding, host_context)

    presentation =
      page_presentation_dto(
        mission,
        spacecraft,
        type_binding,
        applications,
        host_context,
        scope,
        now
      )

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Applications")
     |> assign(:nav_item, :spacecraft)
     |> assign(:type_binding, type_binding)
     |> assign(:application_host_context, host_context)
     |> assign(:presentation, presentation)}
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
      <.vue
        id="spacecraft-applications-page-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="applications"
        host_scope="spacecraft"
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp page_presentation_dto(
         mission,
         spacecraft,
         type_binding,
         applications,
         host_context,
         scope,
         now
       ) do
    mission_id = mission.mission_id
    spacecraft_id = spacecraft.spacecraft_id

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "spacecraft-applications-page",
            "class" => "space-y-6"
          })
      },
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
        "body" => %{
          "attrs" => presentation_attrs(%{"class" => "flex items-end justify-between gap-4"})
        },
        "content" => %{"attrs" => presentation_attrs(%{})},
        "breadcrumbs" => breadcrumbs_presentation(mission, spacecraft),
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => "Applications"
        },
        "subtitle" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
            }),
          "text" =>
            "Install profile-declared product applications and open their host-rendered workspaces."
        },
        "actions" => %{
          "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
          "readiness" => %{
            "attrs" =>
              navigate_attrs(
                ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/readiness",
                %{"class" => "btn btn-ghost btn-sm"}
              ),
            "text" => "Readiness"
          }
        }
      },
      "component" => %{
        "attrs" => presentation_attrs(%{"id" => "spacecraft-applications-component"})
      },
      "profile" => profile_card_dto(type_binding, mission_id, spacecraft_id),
      "applications" =>
        application_rows_dto(applications, host_context, mission, spacecraft, scope, now)
    }
  end

  defp breadcrumbs_presentation(mission, spacecraft) do
    mission_id = mission.mission_id
    spacecraft_id = spacecraft.spacecraft_id

    %{
      "attrs" =>
        presentation_attrs(%{
          "aria-label" => "Breadcrumb",
          "class" =>
            "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        }),
      "items" => [
        breadcrumb_link("mission", nil, mission.display_name, ~p"/missions/#{mission_id}"),
        breadcrumb_link(
          "spacecraft",
          breadcrumb_separator(),
          "Spacecraft",
          ~p"/missions/#{mission_id}/spacecraft"
        ),
        breadcrumb_link(
          "spacecraft-detail",
          breadcrumb_separator(),
          spacecraft.display_name,
          ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}"
        ),
        %{
          "key" => "applications",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Applications"
          }
        }
      ]
    }
  end

  defp breadcrumb_link(key, separator, text, href) do
    %{
      "key" => key,
      "separator" => separator,
      "link" => %{
        "attrs" => navigate_attrs(href, %{"class" => "hover:text-primary transition-colors"}),
        "text" => text
      },
      "current" => nil
    }
  end

  defp breadcrumb_separator do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" => "text-base-content/20",
          "aria-hidden" => "true"
        }),
      "text" => "/"
    }
  end

  defp navigate_attrs(href, extra_attrs) do
    %{
      "href" => href,
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push"
    }
    |> Map.merge(extra_attrs)
    |> presentation_attrs()
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
    now = request_boundary_now()

    applications =
      application_rows(
        socket.assigns.current_scope,
        socket.assigns.type_binding,
        socket.assigns.application_host_context
      )

    presentation =
      page_presentation_dto(
        socket.assigns.current_mission,
        socket.assigns.current_spacecraft,
        socket.assigns.type_binding,
        applications,
        socket.assigns.application_host_context,
        socket.assigns.current_scope,
        now
      )

    assign(socket, :presentation, presentation)
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

  defp application_rows_dto(applications, host_context, mission, spacecraft, scope, now) do
    Enum.map(
      applications,
      &application_row_dto(&1, host_context, mission, spacecraft, scope, now)
    )
  end

  defp application_row_dto(application, host_context, mission, spacecraft, scope, now) do
    card_id = ApplicationInventory.dom_id(host_context, application.application_key)
    route_context = %{host_context: host_context, mission: mission, spacecraft: spacecraft}

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
      manage_path: workspace_path(scope, route_context, application.application_key, now),
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

  defp workspace_path(scope, route_context, application_key, now) do
    case ApplicationHostCatalog.workspace_href(scope, route_context, application_key, now: now) do
      {:ok, path} -> path
      {:error, :invalid_application_request} -> nil
    end
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

  defp request_boundary_now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
