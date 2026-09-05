defmodule CadenceWeb.ApplicationHostLive do
  @moduledoc "Authenticated host for registered mission and spacecraft application surfaces."

  use CadenceWeb, :live_view

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    JSONBoundary,
    SurfaceDefinition
  }

  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.ApplicationSurfaces
  alias Phoenix.LiveView.JS

  alias CadenceWeb.ApplicationSurfaces.{
    Declarative,
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
    raw_action_params = Map.get(params, "application_action", %{})
    action_params = if is_map(raw_action_params), do: raw_action_params, else: %{}

    with :ok <- validate_action_params(raw_action_params),
         true <- action_id in socket.assigns.application_surface_definition.actions,
         request = %ActionRequest{
           application_key: socket.assigns.application_definition.application_key,
           application_version: socket.assigns.application_definition.version,
           action_id: action_id,
           params: action_params
         },
         {:ok, result} <-
           ActionDispatcher.dispatch(
             socket.assigns.current_scope,
             socket.assigns.application_host_context,
             request
           ),
         :ok <- validate_action_output(request.application_key, result),
         {:ok, socket} <- load_declarative_surface(socket) do
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

  @impl true
  def handle_params(
        params,
        _uri,
        %{assigns: %{application_renderer_kind: :declarative}} = socket
      ) do
    query_params = TableEvents.query_params(params)

    if query_params == socket.assigns.application_surface_query_params do
      {:noreply, socket}
    else
      case load_declarative_surface(socket, query_params) do
        {:ok, socket} ->
          {:noreply, socket}

        {:error, _reason} ->
          {:noreply,
           assign(socket, :application_action_feedback, %{
             kind: :error,
             code: "surface_page_failed",
             message: "The requested application page could not be loaded."
           })}
      end
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(%{application_renderer_kind: :federated} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id={application_host_dom_id(@application_host_context)}
        data-application-key={@application_definition.application_key}
        data-application-version={@application_definition.version}
        data-application-installation-id={@application_installation.application_installation_id}
        data-surface-id={@application_surface_definition.surface_id}
        data-surface-version={@application_surface_definition.version}
        data-renderer="federated"
      >
        <.vue
          id="application-surface-component"
          v-component="FederatedFullPageSurface"
          application_key={@application_definition.application_key}
          application_version={@application_definition.version}
          surface_id={@application_surface_definition.surface_id}
          surface_version={@application_surface_definition.version}
          host_scope={Atom.to_string(@application_host_context.placement)}
          organization_id={@application_host_context.organization_id}
          user_id={@application_host_context.user_id}
          mission_id={@application_host_context.mission_id}
          spacecraft_id={@application_host_context.spacecraft_id}
          query_params={@application_surface_query_params}
          v-ssr={false}
          class="contents"
        />
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
        <.vue
          id="application-host-component"
          v-component="ApplicationHost"
          host={application_host_dto(assigns)}
          navigation={surface_navigation_dto(assigns)}
          declarative_surface={
            Declarative.presentation(
              @application_surface_document,
              @application_definition,
              @application_surface_definition,
              @application_surface_form,
              @application_action_feedback
            )
          }
          application_surface_rows={@streams.application_surface_rows}
          application_surface_activity={@streams.application_surface_activity}
          application_surface_packet_groups={@streams.application_surface_packet_groups}
          v-on:application_form_change={JS.push("application_form_change")}
          v-on:application_action={JS.push("application_action")}
          v-on:application_table_page={JS.push("application_table_page")}
          v-ssr={false}
          class="contents"
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

  defp mount_renderer(socket, %SurfaceDefinition{renderer: {:trusted, _renderer_id}}) do
    {:ok, assign(socket, :application_renderer_kind, :federated)}
  end

  defp mount_renderer(
         socket,
         %SurfaceDefinition{renderer: {:declarative, "cadence.host.surface.v1"}}
       ) do
    socket
    |> assign(:application_renderer_kind, :declarative)
    |> stream_configure(:application_surface_rows, dom_id: &Declarative.table_row_dom_id/1)
    |> stream_configure(:application_surface_activity,
      dom_id: &Declarative.activity_item_dom_id/1
    )
    |> stream_configure(:application_surface_packet_groups,
      dom_id: &Declarative.packet_group_dom_id/1
    )
    |> load_declarative_surface()
  end

  defp mount_renderer(_socket, %SurfaceDefinition{}),
    do: {:error, :unsupported_application_renderer}

  defp load_declarative_surface(socket, params \\ nil) do
    params = params || socket.assigns.application_surface_query_params

    with {:ok, document} <-
           ApplicationSurfaces.load(
             socket.assigns.current_scope,
             socket.assigns.application_host_context,
             socket.assigns.application_definition.application_key,
             socket.assigns.application_definition.version,
             socket.assigns.application_surface_definition,
             params
           ) do
      {:ok,
       socket
       |> assign(:application_surface_document, document)
       |> assign(:application_surface_form, declarative_surface_form(document))
       |> assign(:application_surface_query_params, params)
       |> present_declarative_streams(document)}
    end
  end

  defp present_declarative_streams(socket, document) do
    socket
    |> stream(
      :application_surface_rows,
      bounded_collection(Declarative.table_row_dtos(document)),
      reset: true
    )
    |> stream(
      :application_surface_activity,
      bounded_collection(Declarative.activity_item_dtos(document)),
      reset: true
    )
    |> stream(
      :application_surface_packet_groups,
      bounded_collection(Declarative.packet_group_dtos(document)),
      reset: true
    )
  end

  defp declarative_surface_form(%{form: form}) when not is_nil(form) do
    params =
      Map.new(form.fields, fn field ->
        {Atom.to_string(field.field), field.default}
      end)

    to_form(params, as: :application_action)
  end

  defp declarative_surface_form(%{packet_bindings: nil}), do: nil

  defp declarative_surface_form(%{packet_bindings: packet_bindings}) do
    selected_packet_ids =
      packet_bindings.packet_groups
      |> Enum.filter(& &1.selected)
      |> Enum.map(& &1.packet_id)

    to_form(
      %{
        "input_id" => packet_bindings.input_definition.input_id,
        "input_version" => Integer.to_string(packet_bindings.input_definition.version),
        "catalog_revision_id" => packet_bindings.catalog_revision_id || "",
        "source_endpoint_ref" => packet_bindings.source_endpoint_ref || "",
        "expected_configuration_version" => version_value(packet_bindings.configured_version),
        "selected_packet_ids" => selected_packet_ids
      },
      as: :application_action
    )
  end

  defp version_value(nil), do: ""
  defp version_value(version), do: Integer.to_string(version)

  defp failed_surface_form(%{form: nil, packet_bindings: nil}, _params, _failure), do: nil

  defp failed_surface_form(%{form: nil, packet_bindings: _bindings}, params, _failure) do
    to_form(params, as: :application_action)
  end

  defp failed_surface_form(%{form: form_definition}, params, %ActionFailure{} = failure) do
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

  defp application_host_dto(assigns) do
    dto = %{
      dom_id: application_host_dom_id(assigns.application_host_context),
      application_key: assigns.application_definition.application_key,
      application_version: assigns.application_definition.version,
      application_installation_id: assigns.application_installation.application_installation_id,
      surface_id: assigns.application_surface_definition.surface_id,
      renderer: Atom.to_string(assigns.application_renderer_kind)
    }

    bounded_dto(dto, %{
      dom_id: application_host_dom_id(assigns.application_host_context),
      application_key: "unavailable",
      application_version: 0,
      application_installation_id: "unavailable",
      surface_id: "unavailable",
      renderer: "unavailable"
    })
  end

  defp surface_navigation_dto(assigns) do
    if length(assigns.application_workspace_surfaces) > 1 do
      dto = %{
        id: "application-surface-navigation",
        label: "Application surfaces",
        items:
          Enum.map(assigns.application_workspace_surfaces, fn surface ->
            %{
              id: "application-surface-nav-#{surface.surface_id}",
              surface_id: surface.surface_id,
              label: Map.get(surface.navigation, :label, surface.surface_id),
              href:
                application_surface_path(
                  assigns.application_host_context,
                  assigns.application_definition.application_key,
                  surface.surface_id
                ),
              current: surface.surface_id == assigns.application_surface_definition.surface_id
            }
          end)
      }

      bounded_dto(dto, nil)
    end
  end

  defp bounded_dto(value, fallback) do
    case JSONBoundary.validate(value) do
      :ok -> value
      {:error, _reason} -> fallback
    end
  end

  defp bounded_collection(value) when is_list(value) do
    case JSONBoundary.validate(value) do
      :ok -> value
      {:error, _reason} -> []
    end
  end

  defp bounded_collection(_value), do: []

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
      failed_surface_form(socket.assigns.application_surface_document, params, failure)
    )
  end

  defp assign_action_feedback(socket, kind, code, message) do
    assign(socket, :application_action_feedback, %{
      kind: kind,
      code: code,
      message: message
    })
  end

  defp validate_action_params(params) when is_map(params) do
    case JSONBoundary.validate(params) do
      :ok -> :ok
      {:error, _reason} -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp validate_action_params(_params),
    do: {:error, :application_surface_bounds_exceeded}

  defp validate_action_output(application_key, result) do
    output = ActionDispatcher.result(application_key, result)

    cond do
      is_nil(output) -> {:error, :application_action_output_bounds_exceeded}
      JSONBoundary.validate(output) == :ok -> :ok
      true -> {:error, :application_action_output_bounds_exceeded}
    end
  rescue
    _exception -> {:error, :application_action_output_bounds_exceeded}
  catch
    _kind, _value -> {:error, :application_action_output_bounds_exceeded}
  end

  defp action_success_message(socket, action_id) do
    document = socket.assigns.application_surface_document

    case {document.form, document.packet_bindings} do
      {%{action_id: ^action_id, success_message: message}, _packet_bindings}
      when is_binary(message) ->
        message

      {_form, %{action_id: ^action_id}} ->
        "Packet bindings saved. Apply mission changes to make them active."

      _blocks ->
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

  defp action_failure({:packet_binding_configuration_version_conflict, _expected, _current}) do
    %ActionFailure{
      code: "packet_binding_version_conflict",
      message: "Packet bindings changed. Reload the surface and try again."
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
