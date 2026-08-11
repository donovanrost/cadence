defmodule CadenceWeb.SpacecraftTelemetryDecomLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationPreflight,
    HostContext,
    PreflightCheck,
    PreflightReport
  }

  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.ApplicationReferences
  alias CadenceWeb.SpacecraftTelemetryDecomLive.Components

  @impl true
  def mount(_params, _session, socket), do: mount_surface(socket)

  @doc false
  @spec mount_surface(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount_surface(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id
    spacecraft_id = socket.assigns.current_spacecraft.spacecraft_id

    config =
      case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft_id) do
        {:ok, config} -> config
        {:error, :not_configured} -> nil
      end

    definition = application_definition(socket.assigns)
    surface = application_surface_definition(socket.assigns, definition)
    {socket, revisions} = resolve_telemetry_revisions(socket, definition, surface)
    selected_revision_id = (config && config.catalog_revision_id) || first_option_value(revisions)

    apid_rows = load_apid_rows(organization_id, mission_id, selected_revision_id)
    selection = selection_from_config(config)

    {:ok,
     socket
     |> assign(:page_title, "Telemetry Decom")
     |> assign(:nav_item, :spacecraft)
     |> assign(:config, config)
     |> assign(:revisions, revisions)
     |> assign(:selected_revision_id, selected_revision_id)
     |> assign(:apid_rows, apid_rows)
     |> assign(:selection, selection)
     |> assign(:preview, preview_for(organization_id, mission_id, config))
     |> assign(:activation_preflight, activation_preflight(socket, definition))
     |> assign(:active_binding_set_summary, fetch_active_binding_set_summary(mission_id))
     |> assign(
       :pending_activation_request,
       pending_activation_request(socket.assigns.current_scope, mission_id)
     )
     |> assign(:saved_at, config && config.updated_at)}
  end

  defp load_apid_rows(_organization_id, _mission_id, nil), do: []

  defp load_apid_rows(organization_id, mission_id, revision_id) do
    case TelemetryDecom.list_revision_apid_rows(organization_id, mission_id, revision_id) do
      {:ok, %{rows: rows}} -> rows
      {:error, _} -> []
    end
  end

  defp selection_from_config(nil), do: MapSet.new()
  defp selection_from_config(%{handled_apids: apids}), do: MapSet.new(apids)

  @impl true
  def handle_event("change_revision", %{"catalog_revision_id" => revision_id}, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: _sc} = socket.assigns

    apid_rows = load_apid_rows(scope.organization_id, mission.mission_id, revision_id)

    socket =
      socket
      |> assign(:selected_revision_id, revision_id)
      |> assign(:apid_rows, apid_rows)
      |> assign(:selection, MapSet.new())

    save_and_refresh(socket, revision_id: revision_id)
  end

  def handle_event("save_catalog_revision", _params, socket) do
    save_and_refresh(socket)
  end

  def handle_event("enable", _params, socket) do
    case dispatch_action(socket, "request_activation") do
      {:ok, %{config: config, activation_request: request}} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:pending_activation_request, request)
         |> put_flash(
           :info,
           "Telemetry Decom activation requested. A different mission administrator must approve it before the changes become live."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not enable: #{humanize_error(reason)}")}
    end
  end

  def handle_event("disable", _params, socket) do
    case dispatch_action(socket, "disable") do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> refresh_activation_preflight()
         |> put_flash(
           :info,
           "Telemetry Decom disabled for this spacecraft. Apply mission changes to remove it from the live mission."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not disable: #{humanize_error(reason)}")}
    end
  end

  defp save_and_refresh(socket, opts \\ []) do
    revision_id = Keyword.get(opts, :revision_id, socket.assigns.selected_revision_id)

    if revision_id == nil do
      {:noreply, assign(socket, :preview, nil)}
    else
      configure_result =
        dispatch_action(socket, "save_configuration", %{
          catalog_revision_id: revision_id,
          handled_apids: []
        })

      case configure_result do
        {:ok, config} ->
          preview = preview_for(config.organization_id, config.mission_id, config)

          {:noreply,
           socket
           |> assign(:config, config)
           |> assign(:selection, selection_from_config(config))
           |> assign(:preview, preview)
           |> refresh_activation_preflight()
           |> assign(:saved_at, config.updated_at)}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Could not save configuration: #{humanize_error(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Telemetry Decom"
        subtitle={"Application packet inputs and publication state for #{@current_spacecraft.display_name}."}
        breadcrumbs={breadcrumb_items(@current_mission, @current_spacecraft)}
      />

      <.card id="telemetry-decom-card">
        <div class="space-y-4">
          <Components.status_section
            config={@config}
            active={@active_binding_set_summary}
            saved_at={@saved_at}
          />
          <div class="border-t border-base-300/30"></div>

          <%= if @revisions == [] do %>
            <Components.no_revisions_notice current_mission={@current_mission} />
          <% else %>
            <Components.revision_section
              revisions={@revisions}
              selected_revision_id={@selected_revision_id}
            />
            <div class="border-t border-base-300/30"></div>

            <Components.packet_bindings_handoff
              rows={@apid_rows}
              selection={@selection}
              mission={@current_mission}
              spacecraft={@current_spacecraft}
            />
            <div class="border-t border-base-300/30"></div>

            <Components.preview_section preview={@preview} />
          <% end %>

          <div class="border-t border-base-300/30"></div>
          <.application_preflight report={@activation_preflight} />
          <div class="border-t border-base-300/30"></div>

          <Components.apply_section
            config={@config}
            pending_activation_request={@pending_activation_request}
            preflight={@activation_preflight}
            lifecycle_contract={@application_definition.lifecycle_contract}
          />
        </div>
      </.card>
    </div>
    """
  end

  defp breadcrumb_items(mission, spacecraft) do
    [
      {mission.display_name, ~p"/missions/#{mission.mission_id}"},
      {"Spacecraft", ~p"/missions/#{mission.mission_id}/spacecraft"},
      {spacecraft.display_name,
       ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"},
      {"Applications",
       ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"},
      {"Telemetry Decom", nil}
    ]
  end

  defp first_option_value([]), do: nil
  defp first_option_value([{_, value} | _]), do: value

  defp resolve_telemetry_revisions(socket, definition, surface) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    case ApplicationReferences.resolve(
           scope,
           HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
           definition.application_key,
           definition.version,
           surface,
           "catalog_revision_id"
         ) do
      {:ok, page} ->
        options = Enum.map(page.options, &{&1.label, &1.value})
        {socket, options}

      {:error, _reason} ->
        {put_flash(socket, :error, "Catalog revisions could not be loaded. Try again."), []}
    end
  end

  defp preview_for(_organization_id, _mission_id, nil), do: nil

  defp preview_for(organization_id, mission_id, config) do
    case TelemetryDecom.preview(organization_id, mission_id, config) do
      {:ok, preview} -> Map.put(preview, :config, config)
      {:error, _reason} -> nil
    end
  end

  defp fetch_active_binding_set_summary(mission_id) do
    case Cadence.Activations.fetch_active_activation(mission_id) do
      {:ok, activation} ->
        %{
          binding_set_id: activation.binding_set_id,
          binding_set_version: activation.binding_set_version
        }

      {:error, _} ->
        nil
    end
  end

  defp pending_activation_request(current_scope, mission_id) do
    case Cadence.Management.Activations.latest_pending(
           current_scope,
           mission_id,
           TelemetryDecom.binding_set_id(mission_id)
         ) do
      {:ok, request} -> request
      {:error, _reason} -> nil
    end
  end

  defp dispatch_action(socket, action_id, params \\ %{}) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    definition =
      Map.get_lazy(socket.assigns, :application_definition, fn ->
        {:ok, definition} = ExtensionCatalog.fetch_available_application("telemetry_decom")
        definition
      end)

    request = %ActionRequest{
      application_key: definition.application_key,
      application_version: definition.version,
      action_id: action_id,
      params: params,
      expected_configuration_version: installed_configuration_version(socket.assigns)
    }

    ActionDispatcher.dispatch(
      scope,
      HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
      request
    )
  end

  defp refresh_activation_preflight(socket) do
    assign(
      socket,
      :activation_preflight,
      activation_preflight(socket, application_definition(socket.assigns))
    )
  end

  defp activation_preflight(socket, definition) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: spacecraft} =
      socket.assigns

    case ApplicationPreflight.load(
           scope,
           HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
           definition
         ) do
      {:ok, report} -> report
      {:error, _reason} -> unavailable_preflight(definition)
    end
  end

  defp unavailable_preflight(definition) do
    PreflightReport.new(definition, [
      %PreflightCheck{
        id: "host-readiness",
        category: :configuration,
        state: :blocked,
        title: "Preflight unavailable",
        detail: "Cadence could not verify activation readiness for this installation."
      }
    ])
  end

  defp application_definition(assigns) do
    Map.get_lazy(assigns, :application_definition, fn ->
      {:ok, definition} = ExtensionCatalog.fetch_available_application("telemetry_decom")
      definition
    end)
  end

  defp application_surface_definition(assigns, definition) do
    Map.get_lazy(assigns, :application_surface_definition, fn ->
      {:ok, surface} = ApplicationRegistry.fetch_default_surface(definition, :spacecraft)
      surface
    end)
  end

  defp installed_configuration_version(%{
         application_installation: %{configuration_ref: %{version: version}}
       }),
       do: version

  defp installed_configuration_version(_assigns), do: nil

  defp format_apids(apids), do: APIDSelection.format(apids)

  defp humanize_error({:missing_attr, attr}), do: "missing #{attr}"
  defp humanize_error(:handled_apids_required), do: "handled APIDs are required"
  defp humanize_error(:no_enabled_configs), do: "no enabled spacecraft configurations"

  defp humanize_error({:application_preflight_blocked, _application_key}) do
    "resolve the blocking activation checks first"
  end

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
