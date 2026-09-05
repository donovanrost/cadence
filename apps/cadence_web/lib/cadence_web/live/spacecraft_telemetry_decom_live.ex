defmodule CadenceWeb.SpacecraftTelemetryDecomLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.{
    ActionConfirmation,
    ActionDispatcher,
    ActionRequest,
    ApplicationPreflight,
    HostContext,
    LifecycleContract,
    PreflightCheck,
    PreflightReport
  }

  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.ApplicationReferences

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
     |> assign(
       :telemetry_decom_page,
       page_dto(socket.assigns.current_mission, socket.assigns.current_spacecraft)
     )
     |> assign(:telemetry_decom_card, %{id: "telemetry-decom-card"})
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
    # ApplicationHostLive keeps the authenticated Layouts.app wrapper around this trusted surface.
    ~H"""
    <.vue
      id="spacecraft-telemetry-decom-component"
      v-component="FederatedFullPageSurface"
      application_key="spacecraft"
      surface_id="telemetry_decom"
      host_scope="spacecraft"
          mission_id={@current_mission.mission_id}
          spacecraft_id={@current_spacecraft.spacecraft_id}
          query_params={%{mission_id: @current_mission.mission_id, spacecraft_id: @current_spacecraft.spacecraft_id}}
          v-ssr={false}
      class="contents"
    />
    """
  end

  defp page_dto(mission, spacecraft) do
    %{
      id: "spacecraft-telemetry-decom-page",
      title: "Telemetry Decom",
      subtitle: "Application packet inputs and publication state for #{spacecraft.display_name}.",
      breadcrumbs: breadcrumb_dtos(mission, spacecraft)
    }
  end

  defp breadcrumb_dtos(mission, spacecraft) do
    [
      %{
        id: "telemetry-decom-mission-breadcrumb",
        label: mission.display_name,
        href: ~p"/missions/#{mission.mission_id}"
      },
      %{
        id: "telemetry-decom-spacecraft-list-breadcrumb",
        label: "Spacecraft",
        href: ~p"/missions/#{mission.mission_id}/spacecraft"
      },
      %{
        id: "telemetry-decom-spacecraft-breadcrumb",
        label: spacecraft.display_name,
        href: ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
      },
      %{
        id: "telemetry-decom-applications-breadcrumb",
        label: "Applications",
        href:
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
      },
      %{
        id: "telemetry-decom-current-breadcrumb",
        label: "Telemetry Decom",
        href: nil
      }
    ]
  end

  defp status_dto(config, active, saved_at) do
    status = TelemetryDecom.status(config, active)

    %{
      state: Atom.to_string(status),
      tone: status_tone(status),
      label: status_label(status),
      description: status_description(status),
      saved_label: saved_label(saved_at)
    }
  end

  defp status_tone(:applied), do: "ready"
  defp status_tone(:configured), do: "info"
  defp status_tone(:outdated), do: "attention"
  defp status_tone(:disabled), do: "blocked"
  defp status_tone(:not_configured), do: "blocked"

  defp status_label(:applied), do: "Applied"
  defp status_label(:configured), do: "Configured — not yet applied"
  defp status_label(:outdated), do: "Applied configuration is out of date"
  defp status_label(:disabled), do: "Disabled"
  defp status_label(:not_configured), do: "Not configured"

  defp status_description(:applied),
    do: "This configuration is live on the mission."

  defp status_description(:configured),
    do: "Choices are saved. Request mission changes to publish them."

  defp status_description(:outdated),
    do:
      "The saved configuration differs from what is live. Request mission changes to publish the latest state."

  defp status_description(:disabled),
    do:
      "This spacecraft is excluded from Telemetry Decom. Request mission changes to publish the disabled state."

  defp status_description(:not_configured),
    do: "Choose a catalog revision and packet inputs, then apply mission changes."

  defp saved_label(nil), do: nil
  defp saved_label(%DateTime{} = saved_at), do: "Saved #{format_relative(saved_at)}"

  defp revision_dto([], _selected_revision_id), do: nil

  defp revision_dto(revisions, selected_revision_id) do
    %{
      form_id: "telemetry-decom-revision-form",
      field: %{
        id: "telemetry-decom-revision-select",
        name: "catalog_revision_id",
        label: "Catalog revision",
        value: selected_revision_id,
        options: Enum.map(revisions, fn {label, value} -> %{label: label, value: value} end)
      },
      action: %{
        id: "telemetry-decom-save-revision",
        label: "Use revision"
      }
    }
  end

  defp no_revisions_dto([], mission) do
    %{
      message:
        "No packet catalog revisions are available for this mission yet. Import a catalog revision first.",
      action: %{
        label: "Go to catalog",
        href: ~p"/missions/#{mission.mission_id}/catalog"
      }
    }
  end

  defp no_revisions_dto(_revisions, _mission), do: nil

  defp packet_handoff_dto([], _rows, _selection, _mission, _spacecraft), do: nil

  defp packet_handoff_dto(_revisions, rows, selection, mission, spacecraft) do
    %{
      id: "telemetry-decom-packet-bindings-handoff",
      label: "Packet inputs",
      selection_count: MapSet.size(selection),
      row_count: length(rows),
      summary_suffix:
        "packet selectors currently feed Telemetry Decom. Packet and field selection now lives in the shared host surface.",
      detail: "APIDs route traffic; other applications may read the same packets and fields.",
      action: %{
        id: "telemetry-decom-open-packet-bindings",
        label: "Open Packet Bindings",
        href:
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"
      }
    }
  end

  defp preview_dto([], _preview), do: nil

  defp preview_dto(_revisions, nil) do
    %{
      id: "telemetry-decom-preview",
      label: "Preview",
      empty_message: "Select one or more packet APIDs to preview the application input binding.",
      stats: [],
      diagnostics: nil
    }
  end

  defp preview_dto(_revisions, preview) do
    compiler_result = preview.compilation.compiler_result

    %{
      id: "telemetry-decom-preview",
      label: "Preview",
      empty_message: nil,
      stats: [
        %{
          id: "telemetry-decom-preview-matched-packets",
          label: "Matched packets",
          value: length(preview.selected_packets)
        },
        %{
          id: "telemetry-decom-preview-compiled-defs",
          label: "Compiled defs",
          value: length(compiler_result.packet_definitions)
        },
        %{
          id: "telemetry-decom-preview-unassigned-apids",
          label: "Unassigned APIDs",
          value: length(preview.unassigned_apids)
        },
        %{
          id: "telemetry-decom-preview-notices",
          label: "Notices",
          value: length(compiler_result.diagnostics)
        }
      ],
      diagnostics: diagnostics_dto(compiler_result.diagnostics)
    }
  end

  defp diagnostics_dto([]), do: nil

  defp diagnostics_dto(diagnostics) do
    items =
      diagnostics
      |> Enum.sort_by(fn diagnostic ->
        {severity_rank(diagnostic.severity), diagnostic.code, diagnostic_location(diagnostic)}
      end)
      |> Enum.take(20)
      |> Enum.with_index(1)
      |> Enum.map(fn {diagnostic, index} ->
        item_id = "compiler-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"

        %{
          id: "telemetry-decom-diagnostics-item-#{item_id}",
          diagnostic_id: item_id,
          code: diagnostic.code,
          severity: Atom.to_string(diagnostic.severity),
          title: diagnostic_title(diagnostic.code),
          detail: diagnostic.message,
          value: diagnostic_location(diagnostic)
        }
      end)

    severity = overall_diagnostic_severity(items)
    visible_count = length(items)
    total_count = length(diagnostics)

    %{
      id: "telemetry-decom-diagnostics",
      items_id: "telemetry-decom-diagnostics-items",
      role: if(severity == "error", do: "alert", else: "status"),
      severity: severity,
      count: visible_count,
      total_count: total_count,
      count_label: diagnostics_count_label(visible_count, total_count),
      label: diagnostic_severity_label(severity),
      title: "Compiler findings",
      description: "Exceptional conditions from the selected packet compilation preview.",
      items: items
    }
  end

  defp overall_diagnostic_severity(items) do
    cond do
      Enum.any?(items, &(&1.severity == "error")) -> "error"
      Enum.any?(items, &(&1.severity == "warning")) -> "warning"
      true -> "info"
    end
  end

  defp diagnostics_count_label(visible_count, total_count) when visible_count < total_count,
    do: "#{visible_count} shown · #{total_count} total"

  defp diagnostics_count_label(_visible_count, 1), do: "1 finding"

  defp diagnostics_count_label(_visible_count, total_count),
    do: "#{total_count} findings"

  defp diagnostic_severity_label("error"), do: "Blocked"
  defp diagnostic_severity_label("warning"), do: "Advisory"
  defp diagnostic_severity_label("info"), do: "Notice"

  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2

  defp diagnostic_title(code) do
    code
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp diagnostic_location(%{path: []}), do: nil
  defp diagnostic_location(%{path: path}) when is_list(path), do: Enum.join(path, " / ")
  defp diagnostic_location(%{semantic_id: semantic_id}), do: semantic_id
  defp diagnostic_location(_diagnostic), do: nil

  defp preflight_dto(report) do
    %{
      id: "application-activation-preflight",
      checks_id: "application-preflight-checks",
      state: Atom.to_string(report.state),
      activation_ready: PreflightReport.ready?(report),
      check_count: length(report.checks),
      application_version: report.application_version,
      summary: report.summary,
      label: preflight_label(report.state),
      checks:
        Enum.map(report.checks, fn check ->
          %{
            id: "application-preflight-check-#{check.id}",
            check_id: check.id,
            category: Atom.to_string(check.category),
            state: Atom.to_string(check.state),
            title: check.title,
            detail: check.detail,
            value: check.value
          }
        end)
    }
  end

  defp preflight_label(:ready), do: "Ready"
  defp preflight_label(:attention), do: "Advisory"
  defp preflight_label(:blocked), do: "Blocked"

  defp pending_activation_dto(nil), do: nil

  defp pending_activation_dto(request) do
    %{
      id: "telemetry-decom-activation-pending",
      activation_request_id: request.activation_request_id,
      message_before: "Activation request",
      message_after: "is waiting for approval from a different mission administrator."
    }
  end

  defp lifecycle_actions_dto(nil, _pending_request, _preflight, _contract) do
    %{
      empty_message: "Select at least one APID to save and apply.",
      disable: nil,
      enable: nil
    }
  end

  defp lifecycle_actions_dto(config, pending_request, preflight, contract) do
    %{
      empty_message: nil,
      disable:
        if(config.enabled,
          do:
            lifecycle_action_dto(
              contract,
              "disable",
              "disable",
              "telemetry-decom-disable-button"
            )
        ),
      enable:
        lifecycle_action_dto(
          contract,
          "request_activation",
          "enable",
          "telemetry-decom-enable-button",
          not is_nil(pending_request) or not PreflightReport.ready?(preflight)
        )
    }
  end

  defp lifecycle_action_dto(contract, action_id, event, id, disabled \\ false) do
    {:ok, action} = LifecycleContract.fetch_action(contract, action_id)

    %{
      id: id,
      action_id: action.action_id,
      event: event,
      label: action.label,
      variant: Atom.to_string(action.button_variant),
      effect: Atom.to_string(action.effect),
      execution: Atom.to_string(action.execution),
      confirmation: confirmation_dto(action.confirmation),
      disabled: disabled
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

  defp format_relative(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
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
