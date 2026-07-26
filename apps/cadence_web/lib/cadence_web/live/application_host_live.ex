defmodule CadenceWeb.ApplicationHostLive do
  @moduledoc "Authenticated host for registered mission and spacecraft application surfaces."

  use CadenceWeb, :live_view

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    SurfaceDefinition
  }

  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.ExtensionCatalog
  alias CadenceWeb.ApplicationSurfaceRegistry

  alias CadenceWeb.ApplicationSurfaces.{
    Declarative,
    DocumentState,
    ReferenceEvents,
    TableEvents
  }

  @impl true
  def mount(params, _session, socket) do
    host_context = host_context(socket.assigns)

    with {:ok, application_key} <- requested_application_key(params),
         {:ok, _known_definition} <-
           ExtensionCatalog.fetch_available_application(application_key),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             socket.assigns.current_scope,
             host_context,
             application_key
           ),
         {:ok, definition} <-
           ExtensionCatalog.fetch_available_application(
             application_key,
             installation.application_version
           ),
         true <- host_context.placement in definition.installable_scopes,
         {:ok, surface} <- requested_surface(definition, host_context, params),
         {:ok, socket} <-
           socket
           |> assign(:application_installation, installation)
           |> assign(:application_host_context, host_context)
           |> assign(:application_definition, definition)
           |> assign(:application_surface_definition, surface)
           |> assign(:application_action_feedback, nil)
           |> assign(:application_surface_query_params, TableEvents.query_params(params))
           |> assign(
             :application_workspace_surfaces,
             ApplicationRegistry.workspace_surfaces(definition, host_context.placement)
           )
           |> mount_renderer(surface) do
      {:ok, socket}
    else
      {:error, reason}
      when reason in [
             :application_not_installed,
             :application_installation_disabled,
             :application_installation_uninstalled
           ] ->
        application_unavailable(socket, reason)

      _reason ->
        application_not_found(socket)
    end
  end

  @impl true
  def handle_event(
        "application_form_change",
        params,
        %{assigns: %{application_renderer_kind: :declarative}} = socket
      ),
      do: ReferenceEvents.change(params, socket)

  def handle_event(
        "application_action",
        params,
        %{assigns: %{application_renderer_kind: :declarative}} = socket
      ) do
    action_id = Map.get(params, "action-id", Map.get(params, "action_id"))
    action_params = Map.get(params, "application_action", %{})

    with true <- action_id in socket.assigns.application_surface_definition.actions,
         request = %ActionRequest{
           application_key: socket.assigns.application_definition.application_key,
           application_version: socket.assigns.application_definition.version,
           action_id: action_id,
           params: action_params
         },
         {:ok, _result} <-
           ActionDispatcher.dispatch(
             socket.assigns.current_scope,
             socket.assigns.application_host_context,
             request
           ),
         {:ok, socket} <- DocumentState.load(socket) do
      {:noreply,
       assign_action_feedback(
         socket,
         :success,
         "action_completed",
         action_success_message(socket, action_id)
       )}
    else
      false ->
        failure = %ActionFailure{
          code: "action_not_available",
          message: "Action is not available on this surface."
        }

        {:noreply, assign_action_failure(socket, action_params, failure)}

      {:error, reason} ->
        {:noreply, assign_action_failure(socket, action_params, action_failure(reason))}
    end
  end

  def handle_event(
        "application_table_page",
        %{"page" => page},
        %{assigns: %{application_renderer_kind: :declarative}} = socket
      ) do
    surface_path =
      application_surface_path(
        socket.assigns.application_host_context,
        socket.assigns.application_definition.application_key,
        socket.assigns.application_surface_definition.surface_id
      )

    TableEvents.change(page, socket, surface_path)
  end

  def handle_event(event, params, %{assigns: %{application_renderer_kind: :trusted}} = socket) do
    socket.assigns.application_surface_module.handle_event(event, params, socket)
  end

  @impl true
  def handle_params(
        params,
        _uri,
        %{assigns: %{application_renderer_kind: :declarative}} = socket
      ) do
    TableEvents.handle_params(params, socket)
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info(message, socket) do
    case socket.assigns do
      %{application_renderer_kind: :trusted, application_surface_module: surface_module} ->
        if function_exported?(surface_module, :handle_info, 2) do
          surface_module.handle_info(message, socket)
        else
          {:noreply, socket}
        end

      _assigns ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(
        %{application_renderer_kind: :trusted, application_surface_module: surface_module} =
          assigns
      ) do
    rendered_surface = surface_module.render(assigns)
    assigns = assign(assigns, :rendered_application_surface, rendered_surface)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id={application_host_dom_id(@application_host_context)}
        data-application-key={@application_definition.application_key}
        data-application-version={@application_definition.version}
        data-application-installation-id={@application_installation.application_installation_id}
        data-surface-id={@application_surface_definition.surface_id}
      >
        <.surface_navigation
          surfaces={@application_workspace_surfaces}
          current_surface={@application_surface_definition}
          host_context={@application_host_context}
          application_key={@application_definition.application_key}
        />
        {@rendered_application_surface}
      </div>
    </Layouts.app>
    """
  end

  def render(%{application_renderer_kind: :declarative} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id={application_host_dom_id(@application_host_context)}
        data-application-key={@application_definition.application_key}
        data-application-version={@application_definition.version}
        data-application-installation-id={@application_installation.application_installation_id}
        data-surface-id={@application_surface_definition.surface_id}
        data-renderer="declarative"
      >
        <.surface_navigation
          surfaces={@application_workspace_surfaces}
          current_surface={@application_surface_definition}
          host_context={@application_host_context}
          application_key={@application_definition.application_key}
        />
        <Declarative.surface
          document={@application_surface_document}
          application_definition={@application_definition}
          surface_definition={@application_surface_definition}
          form={@application_surface_form}
          action_feedback={@application_action_feedback}
          rows={@streams.application_surface_rows}
          activity_items={@streams.application_surface_activity}
        />
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="application-host"></div>
    </Layouts.app>
    """
  end

  defp mount_renderer(socket, %SurfaceDefinition{renderer: {:trusted, renderer_id}}) do
    with {:ok, surface_module} <- ApplicationSurfaceRegistry.fetch(renderer_id) do
      socket
      |> assign(:application_renderer_kind, :trusted)
      |> assign(:application_surface_module, surface_module)
      |> surface_module.mount()
    end
  end

  defp mount_renderer(
         socket,
         %SurfaceDefinition{renderer: {:declarative, "cadence.host.surface.v1"}}
       ) do
    socket
    |> assign(:application_renderer_kind, :declarative)
    |> stream_configure(:application_surface_rows, dom_id: &"application-surface-row-#{&1.id}")
    |> stream_configure(:application_surface_activity,
      dom_id: &"application-surface-activity-#{&1.id}"
    )
    |> DocumentState.load()
  end

  defp mount_renderer(_socket, %SurfaceDefinition{}),
    do: {:error, :unsupported_application_renderer}

  defp failed_surface_form(nil, _params, _failure), do: nil

  defp failed_surface_form(form_definition, params, %ActionFailure{} = failure) do
    errors =
      case Enum.find(form_definition.fields, fn field ->
             Atom.to_string(field.field) == failure.field
           end) do
        nil -> []
        field -> [{field.field, {failure.message, []}}]
      end

    to_form(params, as: :application_action, errors: errors)
  end

  defp host_context(%{current_mission: mission, current_spacecraft: spacecraft}) do
    HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
  end

  defp host_context(%{current_mission: mission}), do: HostContext.mission(mission.mission_id)

  defp requested_application_key(%{"application_key" => application_key})
       when is_binary(application_key),
       do: {:ok, application_key}

  defp requested_application_key(_params), do: {:error, :application_key_required}

  defp requested_surface(definition, host_context, %{"surface_id" => surface_id}) do
    ApplicationRegistry.fetch_surface(definition, host_context.placement, surface_id)
  end

  defp requested_surface(definition, host_context, _params) do
    ApplicationRegistry.fetch_default_surface(definition, host_context.placement)
  end

  defp application_not_found(socket) do
    {:ok,
     socket
     |> put_flash(:error, "Application not found.")
     |> push_navigate(to: inventory_path(socket.assigns))}
  end

  defp application_unavailable(socket, reason) do
    message =
      case reason do
        :application_not_installed -> "Install the application before opening it."
        :application_installation_disabled -> "Enable the application before opening it."
        :application_installation_uninstalled -> "Reinstall the application before opening it."
      end

    {:ok,
     socket
     |> put_flash(:error, message)
     |> push_navigate(to: inventory_path(socket.assigns))}
  end

  defp inventory_path(%{current_mission: mission, current_spacecraft: spacecraft}) do
    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
  end

  defp inventory_path(%{current_mission: mission}) do
    ~p"/missions/#{mission.mission_id}/applications"
  end

  defp application_host_dom_id(%HostContext{placement: :spacecraft}),
    do: "spacecraft-application-host"

  defp application_host_dom_id(%HostContext{placement: :mission}),
    do: "mission-application-host"

  attr :surfaces, :list, required: true
  attr :current_surface, :any, required: true
  attr :host_context, :any, required: true
  attr :application_key, :string, required: true

  defp surface_navigation(assigns) do
    ~H"""
    <nav
      :if={length(@surfaces) > 1}
      id="application-surface-navigation"
      aria-label="Application surfaces"
      class="mb-5 flex flex-wrap items-center gap-1 border-b border-base-300/70"
    >
      <.link
        :for={surface <- @surfaces}
        id={"application-surface-nav-#{surface.surface_id}"}
        navigate={application_surface_path(@host_context, @application_key, surface.surface_id)}
        aria-current={if(surface.surface_id == @current_surface.surface_id, do: "page", else: nil)}
        class={[
          "relative -mb-px border-b-2 px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition-colors",
          surface.surface_id == @current_surface.surface_id &&
            "border-primary text-primary",
          surface.surface_id != @current_surface.surface_id &&
            "border-transparent text-base-content/55 hover:border-base-content/30 hover:text-base-content"
        ]}
      >
        {Map.get(surface.navigation, :label, surface.surface_id)}
      </.link>
    </nav>
    """
  end

  defp application_surface_path(
         %HostContext{placement: :mission, mission_id: mission_id},
         application_key,
         surface_id
       ) do
    ~p"/missions/#{mission_id}/applications/#{application_key}/#{surface_id}"
  end

  defp application_surface_path(
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         application_key,
         surface_id
       ) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/applications/#{application_key}/#{surface_id}"
  end

  defp assign_action_failure(socket, params, %ActionFailure{} = failure) do
    socket
    |> assign_action_feedback(:error, failure.code, failure.message)
    |> assign(
      :application_surface_form,
      failed_surface_form(socket.assigns.application_surface_document.form, params, failure)
    )
  end

  defp assign_action_feedback(socket, kind, code, message) do
    assign(socket, :application_action_feedback, %{
      kind: kind,
      code: code,
      message: message
    })
  end

  defp action_success_message(socket, action_id) do
    case socket.assigns.application_surface_document.form do
      %{action_id: ^action_id, success_message: message} when is_binary(message) ->
        message

      _form ->
        "Application action completed."
    end
  end

  defp action_failure(%ActionFailure{} = failure), do: failure

  defp action_failure(%Ecto.Changeset{errors: [{field, {message, _opts}} | _errors]}) do
    %ActionFailure{
      code: "invalid_configuration",
      message: message,
      field: Atom.to_string(field)
    }
  end

  defp action_failure(:forbidden) do
    %ActionFailure{
      code: "forbidden",
      message: "You do not have authority to perform this action."
    }
  end

  defp action_failure({:application_configuration_version_conflict, _expected, _current}) do
    %ActionFailure{
      code: "configuration_version_conflict",
      message: "The application configuration changed. Reload the surface and try again."
    }
  end

  defp action_failure(:application_installation_disabled) do
    %ActionFailure{
      code: "application_disabled",
      message: "The application workspace was disabled. Return to Applications to enable it."
    }
  end

  defp action_failure(:application_installation_uninstalled) do
    %ActionFailure{
      code: "application_uninstalled",
      message: "The application was uninstalled. Return to Applications to reinstall it."
    }
  end

  defp action_failure({:application_preflight_blocked, _application_key}) do
    %ActionFailure{
      code: "activation_preflight_blocked",
      message: "Resolve the blocking activation checks before requesting mission changes."
    }
  end

  defp action_failure(_reason) do
    %ActionFailure{
      code: "application_action_failed",
      message: "The application could not complete this action."
    }
  end
end
