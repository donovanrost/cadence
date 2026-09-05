defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole.Presentation do
  @moduledoc "Phoenix-owned presentation adapter for the deep Ops route cohort."

  alias Cadence.Dashboards.Document
  alias Cadence.Auth.Policy

  @spec dashboard(map(), map(), map(), :view | :edit) :: map()
  def dashboard(scope, mission, params, mode) do
    dashboard_id = params["dashboard_id"]
    document_mode = if mode == :edit, do: :edit, else: :view

    {:ok, %Document{} = document} =
      Cadence.Dashboards.fetch_document_for_mode(
        scope.organization_id,
        mission.mission_id,
        dashboard_id,
        document_mode
      )

    %{
      "page" => %{
        "id" => "ops-dashboard-#{mode}-page",
        "mission_id" => mission.mission_id,
        "dashboard_id" => dashboard_id,
        "mode" => Atom.to_string(mode),
        "header" => %{
          "eyebrow" => "Mission operations / Dashboard",
          "heading" => document.name || "Dashboard",
          "copy" => document.description || "Phoenix-owned mission dashboard state."
        }
      },
      "canvas" => canvas(document, mode),
      "editor_guard" => %{"editor_dirty" => false}
    }
  end

  @spec dashboard_activity(map(), map(), map()) :: map()
  def dashboard_activity(scope, mission, params) do
    dashboard_id = params["dashboard_id"]

    {:ok, %Document{} = document} =
      Cadence.Dashboards.fetch_document(scope.organization_id, mission.mission_id, dashboard_id)

    versions =
      Cadence.Dashboards.list_versions(scope.organization_id, mission.mission_id, dashboard_id)

    events =
      Cadence.Dashboards.list_lifecycle_events(
        scope.organization_id,
        mission.mission_id,
        dashboard_id
      )

    selected = selected_version(versions, params["version"])

    author? =
      Policy.authorize(scope, :author_dashboards, %{
        organization_id: scope.organization_id,
        mission_id: mission.mission_id
      }) == :ok

    %{
      "page" => %{
        "id" => "dashboard-activity-page",
        "dashboard_id" => dashboard_id,
        "header" => %{
          "eyebrow" => "Dashboard / Activity",
          "heading" => document.name || "Dashboard",
          "copy" =>
            "Immutable drafts, semantic change summaries, publication, and lifecycle audit."
        },
        "actions" => %{
          "editor" => %{
            "id" => "dashboard-activity-editor",
            "label" => "Edit Dashboard",
            "href" => "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/edit",
            "visible" => author?
          },
          "viewer" => %{
            "id" => "dashboard-activity-viewer",
            "label" => "Viewer",
            "href" => "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}",
            "visible" => true
          }
        },
        "versions" => %{
          "label" => "Versions",
          "count_id" => "dashboard-version-count",
          "count" => length(versions),
          "container_id" => "dashboard-versions",
          "empty_id" => "dashboard-versions-empty",
          "empty" => "No saved versions."
        },
        "activity" => %{
          "label" => "Lifecycle audit",
          "count_id" => "dashboard-activity-count",
          "count" => length(events),
          "container_id" => "dashboard-activity-events",
          "empty_id" => "dashboard-activity-empty",
          "empty" => "No lifecycle transitions recorded."
        }
      },
      "selected_version_number" => value(selected, :version),
      "selected_version_detail" => selected_detail_or_nil(selected, dashboard_id, author?),
      "dashboard_versions" => Enum.map(versions, &version_dto(&1, mission, dashboard_id)),
      "dashboard_activity" => Enum.map(events, &activity_dto/1)
    }
  end

  @spec data_sources(map(), map(), map(), :reader | :registration | :settings) :: map()
  def data_sources(scope, mission, params, mode) do
    sources =
      Cadence.Reads.DataSources.list_data_sources(scope.organization_id, mission.mission_id)

    bindings =
      Cadence.Reads.DataSources.list_data_bindings(scope.organization_id, mission.mission_id)

    selected_id = params["data_source_id"]

    page = %{
      "id" => "ops-data-sources-page",
      "mode" => if(mode == :reader, do: "reader", else: "admin"),
      "focus" => focus(selected_id),
      "header" => %{
        "heading" => if(mode == :reader, do: "Data Sources", else: "Data Source Settings"),
        "mission_id" => mission.mission_id,
        "register_link" => nil,
        "stats" => [
          %{"label" => "sources", "value" => length(sources)},
          %{"label" => "bindings", "value" => length(bindings)},
          %{"label" => "health", "value" => 0}
        ],
        "readiness_policy" => %{
          "id" => "source-readiness-policy",
          "label" => "readiness policy",
          "policy_id" => "mission-default",
          "block_source_health" => true,
          "block_freshness" => true,
          "block_connection_test" => true,
          "connection_summary" => "connection checks are Phoenix-owned"
        }
      },
      "bindings" => %{
        "heading" => "Bindings",
        "description" => "grouped by logical source and realm",
        "empty" => "No dashboard source bindings registered.",
        "groups" => []
      },
      "sources" => %{
        "heading" => "Physical Sources",
        "subtitle" => "Registered adapter-backed stores",
        "empty" => "No data sources registered.",
        "rows" => Enum.map(sources, &source_row(&1, selected_id))
      },
      "deployment_runs" => %{
        "heading" => "Deployment Runs",
        "subtitle" => "TSDB backend lifecycle jobs",
        "empty" => "No deployment runs recorded.",
        "rows" => []
      },
      "activity" => %{
        "binding_events" => event_list("dashboard-data-binding-events", "Recent Binding Events"),
        "source_events" => event_list("dashboard-data-source-events", "Recent Source Events"),
        "health_events" => event_list("dashboard-source-health-events", "Recent Source Health")
      }
    }

    page =
      case mode do
        :registration -> Map.put(page, "admin", %{"registration" => registration_form()})
        :settings -> Map.put(page, "admin", %{"binding_form" => nil})
        :reader -> page
      end

    %{"page" => page}
  end

  @spec data_operations(map(), map(), map(), :reader | :manage) :: map()
  def data_operations(scope, mission, params, mode) do
    _ = scope
    selected_group_id = params["group"]

    %{
      "page" => %{
        "id" => "ops-data-operations-page",
        "selected_group_id" => selected_group_id,
        "groups_empty" => true,
        "navigation" => %{
          "manage" =>
            if(mode == :reader,
              do:
                link(
                  "data-operations-manage-link",
                  "Manage recovery",
                  "/missions/#{mission.mission_id}/ops/data-operations/manage"
                ),
              else: nil
            ),
          "reader" =>
            if(mode == :manage,
              do:
                link(
                  "data-operations-reader-link",
                  "Reader view",
                  "/missions/#{mission.mission_id}/ops/data-operations"
                ),
              else: nil
            )
        }
      },
      "request_form" => request_form(),
      "selected_group" => nil,
      "data_operation_groups" => []
    }
  end

  defp canvas(document, mode) do
    %{
      "root" => %{
        "attrs" => %{"id" => "ops-dashboard-canvas", "data-dashboard-id" => document.dashboard_id}
      },
      "content" => %{"attrs" => %{"class" => "space-y-4"}},
      "groups" => [],
      "controller" => %{"props" => %{"edit_mode" => mode == :edit}},
      "document" => %{"name" => document.name, "description" => document.description}
    }
  end

  defp selected_version([], _version), do: nil
  defp selected_version(versions, nil), do: List.last(versions)

  defp selected_version(versions, version) do
    case Integer.parse(to_string(version)) do
      {number, ""} -> Enum.find(versions, &(value(&1, :version) == number)) || List.last(versions)
      _invalid -> List.last(versions)
    end
  end

  defp selected_detail_or_nil(version, dashboard_id, author?),
    do: selected_detail(version, dashboard_id, author?)

  defp selected_detail(version, dashboard_id, author?) do
    document = value(version, :document) || %{}

    %{
      "version" => value(version, :version),
      "change_summary" => value(version, :change_summary) || "Dashboard created",
      "actions" => %{
        "visible" => author?,
        "restore" => %{
          "id" => "dashboard-activity-restore",
          "label" => "Restore as Draft",
          "disabled" => true,
          "payload" => %{
            "dashboard_id" => dashboard_id,
            "version" => to_string(value(version, :version))
          }
        },
        "publish" => %{
          "id" => "dashboard-activity-publish",
          "label" => "Publish Version",
          "disabled" => true,
          "payload" => %{
            "dashboard_id" => dashboard_id,
            "version" => to_string(value(version, :version))
          }
        }
      },
      "details" => [
        %{"label" => "Widgets", "value" => length(value(document, :placements) || [])},
        %{"label" => "Sections", "value" => length(value(document, :sections) || [])},
        %{"label" => "Changed fields", "value" => "server summary"}
      ]
    }
  end

  defp version_dto(version, mission, dashboard_id) do
    number = value(version, :version)

    %{
      "id" => value(version, :dashboard_version_id),
      "__dom_id" => "dashboard-version-#{number}",
      "version" => number,
      "href" =>
        "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}/activity?version=#{number}",
      "snapshot_kind" => to_string(value(version, :snapshot_kind)),
      "change_summary" => value(version, :change_summary) || "Dashboard created",
      "saved" => to_string(value(version, :created_by) || "system")
    }
  end

  defp activity_dto(event) do
    id = value(event, :dashboard_lifecycle_event_id)

    %{
      "id" => id,
      "__dom_id" => "dashboard-activity-#{id}",
      "dashboard_lifecycle_event_id" => id,
      "event_type" => to_string(value(event, :event_type)),
      "label" => to_string(value(event, :event_type)),
      "occurred" => to_string(value(event, :occurred_at) || ""),
      "dashboard_version" => value(event, :dashboard_version)
    }
  end

  defp focus(nil), do: %{"state" => "none", "data_source_id" => nil}
  defp focus(data_source_id), do: %{"state" => "source", "data_source_id" => data_source_id}

  defp source_row(source, selected_id) do
    id = value(source, :data_source_id) || value(source, :id)

    base = %{
      "data_source_id" => id,
      "focused" => id == selected_id,
      "status_text" => to_string(value(source, :status) || "unknown"),
      "kind_text" => to_string(value(source, :kind) || "unknown"),
      "owner_text" => to_string(value(source, :owner) || "mission"),
      "isolation_text" => "mission",
      "adapter_text" => to_string(value(source, :logical_source) || "unknown"),
      "credential_ref_text" => "",
      "credential_state_text" => "",
      "credential_provider_text" => "",
      "credential_version_text" => "",
      "credential_material_state_text" => "",
      "credential_endpoint_text" => "",
      "credential_secret_fields_text" => "",
      "deployment_status_text" => "",
      "deployment_mode_text" => "",
      "deployment_backend_text" => "",
      "deployment_boundary_text" => "",
      "deployment_job_id_text" => "",
      "deployment_run_id_text" => "",
      "deployment_remediation_text" => "",
      "deployment_lifecycle_operation_text" => "",
      "deployment_lifecycle_status_text" => "",
      "deployment_lifecycle_observed_at_text" => "",
      "capability_text" => "",
      "supported_sampling_text" => "",
      "supported_products_text" => "",
      "supported_metric_history_products_text" => "",
      "supported_product_families_text" => "",
      "health_status" => "unknown",
      "health_reason_text" => "",
      "probe_policy_text" => "",
      "probe_stale_after_ms_text" => "",
      "source_readiness_status" => "unknown",
      "source_readiness_policy_id" => "mission-default",
      "source_readiness_reason_text" => "",
      "probe_kind_text" => "",
      "probe_message_text" => "",
      "probe_metadata_text" => "",
      "probe_diagnostic_kind_text" => "",
      "probe_diagnostic_stage_text" => "",
      "probe_remediation_text" => "",
      "connection_test_result_text" => "",
      "connection_test_kind_text" => "",
      "connection_test_message_text" => "",
      "watermark_text" => "",
      "watermark_confidence_text" => "",
      "detail_link" => link("data-source-#{id}", "Details", "#")
    }

    Map.put(base, "settings_link", link("data-source-settings-#{id}", "Settings", "#"))
  end

  defp event_list(id, heading),
    do: %{"id" => id, "heading" => heading, "subtitle" => "Phoenix-owned events", "rows" => []}

  defp registration_form do
    %{
      "id" => "data-source-registration",
      "heading" => "Register a data source",
      "description" => "Registration remains a Phoenix-owned administrator operation.",
      "form" => %{
        "id" => "data-source-registration-form",
        "values" => %{},
        "options" => %{
          "logical_source" => [],
          "kind" => [],
          "isolation_level" => [],
          "credential_provider" => [],
          "storage" => []
        },
        "error" => nil
      }
    }
  end

  defp request_form do
    fields =
      Map.new(
        ~w(workflow run_id realm data_source_id source_binding_id point_ids source_from source_to reason confirmed),
        fn key ->
          {key,
           %{
             "id" => "data-operation-#{key}",
             "name" => key,
             "type" => if(key == "confirmed", do: "checkbox", else: "text"),
             "label" => key,
             "placeholder" => nil,
             "options" => []
           }}
        end
      )

    %{
      "id" => "historical-workflow-form",
      "values" => %{},
      "fields" => fields,
      "hidden_fields" => [],
      "error" => nil,
      "submit" => %{"id" => "record-request", "label" => "Request workflow"}
    }
  end

  defp link(id, label, href), do: %{"id" => id, "label" => label, "href" => href}
  defp value(value, key), do: Map.get(value, key)
end
