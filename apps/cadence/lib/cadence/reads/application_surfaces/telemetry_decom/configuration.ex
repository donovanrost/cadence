defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecom.Configuration do
  @moduledoc "Scoped Telemetry Decom configuration, compiler preview and governed readiness."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{
    ApplicationPreflight,
    ConfigurationLock,
    HostContext,
    JSONBoundary,
    PreflightReport,
    SurfaceQueryRequest,
    TelemetryDecom
  }

  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.TelemetryDecom.Review
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.Management.Activations
  alias Cadence.Missions
  alias Cadence.SpacecraftStore

  import Cadence.Reads.Spacecraft.Presentation

  @impl true
  def application_key, do: "telemetry_decom"

  @impl true
  def load(%Scope{} = scope, %HostContext{placement: :spacecraft} = host, %SurfaceQueryRequest{
        application_key: "telemetry_decom",
        application_version: 1,
        surface_id: "manage",
        surface_version: 1,
        query_id: "cadence.telemetry_decom.manage",
        query_version: 1,
        params: params
      })
      when map_size(params) == 0 do
    with {:ok, mission} <- Missions.fetch_mission(scope.organization_id, host.mission_id),
         {:ok, data} <- load(scope, host, mission),
         {:ok, data} <- JSONBoundary.safe(data) do
      {:ok,
       %{
         "data" => data,
         "navigation" => %{
           "fallback_href" =>
             "#{mission_path(mission)}/spacecraft/#{host.spacecraft_id}/applications",
           "breadcrumbs" => data["page"]["breadcrumbs"]
         }
       }}
    end
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  def load(%Scope{} = scope, %HostContext{} = host_context, mission) do
    ConfigurationLock.run(mission.organization_id, mission.mission_id, fn ->
      load_configuration(scope, host_context, mission)
    end)
  end

  defp load_configuration(%Scope{} = scope, %HostContext{} = host_context, mission) do
    with true <-
           scope.organization_id == mission.organization_id and
             host_context.mission_id == mission.mission_id and
             (is_nil(scope.mission_id) or scope.mission_id == mission.mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: mission.organization_id,
             mission_id: mission.mission_id
           }),
         {:ok, spacecraft} <- fetch_host_spacecraft(mission, host_context),
         revisions <- Catalog.list_revisions(mission.organization_id, mission.mission_id),
         {:ok, config} <- optional_config(mission, spacecraft),
         :ok <- ensure_revision(revisions, config),
         {:ok, active} <- active_activation(mission),
         {:ok, report} <-
           ApplicationPreflight.load(scope, host_context, TelemetryDecom.definition()),
         {:ok, pending} <-
           Activations.latest_pending(
             scope,
             mission.mission_id,
             TelemetryDecom.binding_set_id(mission.mission_id)
           ),
         {:ok, preview} <- preview(mission, config) do
      selected = config && config.catalog_revision_id

      revision =
        Enum.find(revisions, &(&1.catalog_revision_id == selected))

      status_value = TelemetryDecom.status(config, active)
      preflight = telemetry_preflight(report)

      {:ok,
       %{
         "contract_version" => 1,
         "context" => %{
           "organization_id" => mission.organization_id,
           "mission_id" => mission.mission_id,
           "spacecraft_id" => spacecraft.spacecraft_id
         },
         "configuration" => configuration(config),
         "review" => review(mission, spacecraft),
         "page" => %{
           "id" => "spacecraft-telemetry-decom-page",
           "title" => "Telemetry Decom",
           "subtitle" =>
             "Application packet inputs and publication state for #{spacecraft.display_name}.",
           "breadcrumbs" =>
             [
               breadcrumb(mission.display_name, mission_path(mission)),
               breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
               breadcrumb(
                 spacecraft.display_name,
                 spacecraft_path(mission, spacecraft.spacecraft_id)
               ),
               breadcrumb("Applications", applications_path(mission, spacecraft)),
               breadcrumb("Telemetry Decom", nil)
             ]
             |> Enum.with_index()
             |> Enum.map(fn {crumb, index} ->
               Map.put(crumb, "id", "telemetry-decom-breadcrumb-#{index}")
             end)
         },
         "card" => %{"id" => "telemetry-decom-card"},
         "status" => telemetry_status(status_value, config),
         "revision" => revision_dto(revisions, revision),
         "no_revisions" =>
           if(revisions == [],
             do: %{
               "message" => "Import a catalog revision before configuring Telemetry Decom.",
               "action" => %{
                 "id" => "telemetry-decom-open-catalog",
                 "label" => "Open Catalog",
                 "href" => "#{mission_path(mission)}/catalog"
               }
             },
             else: nil
           ),
         "packet_handoff" => packet_handoff(spacecraft, config, preview, mission),
         "preview" => telemetry_preview(preview),
         "preflight" => preflight,
         "pending_activation" => pending_activation(pending),
         "lifecycle_actions" => telemetry_actions(config, report, pending, mission)
       }}
    else
      false -> {:error, :invalid_application_scope}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_revision(_revisions, nil), do: :ok

  defp ensure_revision(revisions, config) do
    if Enum.any?(revisions, &(&1.catalog_revision_id == config.catalog_revision_id)),
      do: :ok,
      else: {:error, :catalog_revision_unavailable}
  end

  defp active_activation(mission) do
    case Cadence.Activations.fetch_active_activation(mission.organization_id, mission.mission_id) do
      {:ok, active} ->
        {:ok,
         %{binding_set_id: active.binding_set_id, binding_set_version: active.binding_set_version}}

      {:error, :no_active_binding_set} ->
        {:ok, nil}
    end
  end

  defp review(mission, spacecraft) do
    review =
      Review.snapshot(mission.organization_id, mission.mission_id, spacecraft.spacecraft_id)

    spacecraft_names =
      (review["configurations"] ++ review["packet_inputs"])
      |> Enum.map(& &1["spacecraft_id"])
      |> Enum.uniq()
      |> Enum.chunk_every(100)
      |> Enum.flat_map(fn ids ->
        {:ok, names} =
          SpacecraftStore.display_names(mission.organization_id, mission.mission_id, ids)

        names
      end)
      |> Map.new(&{&1["id"], &1["name"]})

    endpoint_names =
      Cadence.SourceEndpoints.display_names(
        mission.organization_id,
        mission.mission_id,
        Enum.map(review["configurations"], & &1["source_endpoint_id"])
      )

    review
    |> Map.update!("configurations", fn entries ->
      Enum.map(entries, fn entry ->
        Map.merge(entry, %{
          "spacecraft_name" => spacecraft_names[entry["spacecraft_id"]],
          "source_endpoint_name" => endpoint_names[entry["source_endpoint_id"]]
        })
      end)
    end)
    |> Map.update!("packet_inputs", fn entries ->
      Enum.map(entries, &Map.put(&1, "spacecraft_name", spacecraft_names[&1["spacecraft_id"]]))
    end)
  end

  defp configuration(nil), do: nil

  defp configuration(config) do
    %{
      "catalog_revision_id" => config.catalog_revision_id,
      "source_endpoint_id" => config.source_endpoint_id,
      "configuration_version" => config.configuration_version,
      "enabled" => config.enabled,
      "handled_apids" => config.handled_apids
    }
  end

  defp preview(_mission, nil), do: {:ok, nil}

  defp preview(mission, config),
    do: TelemetryDecom.preview(mission.organization_id, mission.mission_id, config)

  defp telemetry_preview(nil), do: nil

  defp telemetry_preview(preview) do
    compiled = preview.compilation.compiler_result

    %{
      "id" => "telemetry-decom-preview",
      "label" => "Saved configuration preview",
      "empty_message" => nil,
      "stats" => [
        preview_stat("packets", "Selected packets", length(preview.selected_packets)),
        preview_stat("definitions", "Compiled definitions", length(compiled.packet_definitions)),
        preview_stat("unassigned", "Unassigned APIDs", length(preview.unassigned_apids))
      ],
      "diagnostics" => diagnostics(compiled.diagnostics)
    }
  end

  defp preview_stat(id, label, value),
    do: %{"id" => "telemetry-decom-preview-#{id}", "label" => label, "value" => value}

  defp diagnostics([]), do: nil

  defp diagnostics(items) do
    severity =
      cond do
        Enum.any?(items, &(&1.severity == :error)) -> "error"
        Enum.any?(items, &(&1.severity == :warning)) -> "warning"
        true -> "info"
      end

    %{
      "id" => "telemetry-decom-diagnostics",
      "items_id" => "telemetry-decom-diagnostic-items",
      "role" => if(severity == "error", do: "alert", else: "status"),
      "severity" => severity,
      "count" => min(length(items), 100),
      "total_count" => length(items),
      "count_label" => "#{min(length(items), 100)} of #{length(items)} diagnostics",
      "label" => humanize(severity),
      "title" => "Compiler diagnostics",
      "description" => "Evidence from the saved catalog revision and selected packet set.",
      "items" =>
        items
        |> Enum.take(100)
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          %{
            "id" => "telemetry-decom-diagnostic-#{index}",
            "diagnostic_id" => to_string(index),
            "code" => to_string(item.code),
            "severity" => to_string(item.severity),
            "title" => humanize(item.code),
            "detail" => item.message,
            "value" => nil
          }
        end)
    }
  end

  defp telemetry_preflight(report) do
    %{
      "id" => "telemetry-decom-preflight",
      "state" => to_string(report.state),
      "activation_ready" => PreflightReport.ready?(report),
      "check_count" => length(report.checks),
      "application_version" => report.application_version,
      "summary" => report.summary,
      "label" => humanize(report.state),
      "checks_id" => "telemetry-decom-preflight-checks",
      "checks" =>
        Enum.map(report.checks, fn check ->
          %{
            "id" => "telemetry-decom-check-#{check.id}",
            "check_id" => check.id,
            "category" => to_string(check.category),
            "state" => to_string(check.state),
            "title" => check.title,
            "detail" => check.detail,
            "value" => check.value
          }
        end)
    }
  end

  defp pending_activation(nil), do: nil

  defp pending_activation(request) do
    %{
      "id" => "telemetry-decom-pending-activation",
      "activation_request_id" => request.activation_request_id,
      "message_before" => "Mission changes await approval in request ",
      "message_after" => ". This request may include other spacecraft."
    }
  end

  defp telemetry_actions(config, report, pending, mission) do
    workspace? =
      ConfigurationDrafts.saved_for_mission?(mission.organization_id, mission.mission_id)

    %{
      "disable" =>
        if(config && config.enabled,
          do: lifecycle_action("disable", "Disable workspace", "secondary", false),
          else: nil
        ),
      "enable" =>
        if(config && !workspace?,
          do:
            lifecycle_action(
              "request_activation",
              "Request mission changes",
              "primary",
              not PreflightReport.ready?(report) or not is_nil(pending)
            ),
          else: nil
        ),
      "empty_message" =>
        cond do
          workspace? ->
            "Review and activate these settings in the spacecraft configuration’s Changes section."

          is_nil(config) ->
            "Save a catalog revision, then choose packet inputs before requesting mission changes."

          true ->
            nil
        end
    }
  end

  defp revision_dto([], _revision), do: nil

  defp revision_dto(revisions, revision) do
    %{
      "form_id" => "telemetry-decom-revision-form",
      "field" => %{
        "id" => "telemetry-decom-revision-select",
        "name" => "catalog_revision_id",
        "label" => "Catalog revision",
        "value" => (revision && revision.catalog_revision_id) || "",
        "options" =>
          Enum.map(
            revisions,
            &%{
              "label" => "#{&1.revision_label} (v#{&1.revision_number})",
              "value" => &1.catalog_revision_id
            }
          )
      },
      "action" => %{"id" => "telemetry-decom-save-revision", "label" => "Use revision"}
    }
  end

  defp packet_handoff(_spacecraft, nil, _preview, _mission), do: nil

  defp packet_handoff(spacecraft, config, preview, mission) do
    selected = (config && length(config.handled_apids)) || 0

    %{
      "id" => "telemetry-decom-packet-handoff",
      "label" => "Packet inputs",
      "selection_count" => selected,
      "row_count" => selected + length(preview.unassigned_apids),
      "summary_suffix" => "selected",
      "detail" => "APID selection is managed by the packet binding surface.",
      "action" => %{
        "id" => "telemetry-decom-open-packet-bindings",
        "label" => "Open packet bindings",
        "href" => "#{applications_path(mission, spacecraft)}/telemetry_decom/packet_bindings"
      }
    }
  end

  defp optional_config(mission, spacecraft) do
    case TelemetryDecom.fetch_config(
           mission.organization_id,
           mission.mission_id,
           spacecraft.spacecraft_id
         ) do
      {:ok, config} -> {:ok, config}
      {:error, :not_configured} -> {:ok, nil}
    end
  end

  defp fetch_host_spacecraft(mission, %HostContext{
         placement: :spacecraft,
         spacecraft_id: spacecraft_id
       }) do
    SpacecraftStore.fetch_spacecraft(mission.organization_id, mission.mission_id, spacecraft_id)
  end

  defp applications_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/applications"

  defp telemetry_status(state, config),
    do: %{
      "state" => to_string(state),
      "tone" =>
        if(state == :applied,
          do: "ready",
          else: if(state in [:disabled, :not_configured], do: "blocked", else: "attention")
        ),
      "label" => humanize(state),
      "description" => "Telemetry Decom configuration and publication state.",
      "saved_label" => config && "v#{config.configuration_version}"
    }

  defp lifecycle_action(action_id, label, variant, disabled) do
    prompt =
      if(action_id == "disable",
        do:
          "Disable this workspace and its saved configuration? Manage the installation from Applications to restore access. Live changes still require a mission activation request.",
        else:
          "Request approval of mission changes? The composed request may include other spacecraft configurations."
      )

    %{
      "id" => "telemetry-decom-#{action_id}",
      "action_id" => action_id,
      "event" => if(action_id == "disable", do: "disable", else: "enable"),
      "label" => label,
      "variant" => variant,
      "disabled" => disabled,
      "effect" => "durable",
      "execution" =>
        if(action_id == "request_activation", do: "approval_required", else: "immediate"),
      "confirmation" => %{
        "title" => label,
        "message" => prompt,
        "prompt" => prompt,
        "confirm_label" => label,
        "tone" => "attention"
      }
    }
  end
end
