defmodule CadenceWeb.OpsDataSourcesLive.Page do
  @moduledoc false

  use CadenceWeb, :html

  alias Phoenix.LiveView.JS

  alias CadenceWeb.OpsDataSourcesLive.{
    SourceFocus,
    SourceFocusPresentation,
    SourceFocusResources,
    SourceRegistration
  }

  @binding_row_fields ~w(
    logical_source_text realm_text binding_status data_source_id dataset_text priority_text
    version_text active_from_text active_to_text current_event_id_text source_status_text
    source_kind_text source_owner_text source_isolation_text source_adapter_text
    credential_ref_text health_status health_reason_text health_observed_at_text
    health_event_type_text source_readiness_status source_readiness_policy_id
    source_readiness_reason_text
  )a

  @source_row_fields ~w(
    data_source_id status_text kind_text owner_text isolation_text adapter_text
    credential_ref_text credential_state_text credential_provider_text credential_version_text
    credential_material_state_text credential_endpoint_text credential_secret_fields_text
    deployment_status_text deployment_mode_text deployment_backend_text deployment_boundary_text
    deployment_job_id_text deployment_run_id_text deployment_remediation_text
    deployment_lifecycle_operation_text deployment_lifecycle_status_text
    deployment_lifecycle_observed_at_text capability_text supported_sampling_text
    supported_products_text supported_metric_history_products_text supported_product_families_text
    health_status health_reason_text probe_policy_text probe_stale_after_ms_text
    source_readiness_status source_readiness_policy_id source_readiness_reason_text probe_kind_text
    probe_message_text probe_metadata_text probe_diagnostic_kind_text probe_diagnostic_stage_text
    probe_remediation_text connection_test_result_text connection_test_kind_text
    connection_test_message_text watermark_text watermark_confidence_text
  )a

  @deployment_run_fields ~w(
    job_id run_id data_source_id status_text mode_text backend_text physical_boundary_text
    attempt_count_text failure_summary started_at_text completed_at_text remediation
  )a

  @event_row_fields ~w(
    id event_type title subtitle occurred_at probe_kind probe_message probe_metadata
    probe_diagnostic_kind probe_diagnostic_stage probe_remediation connection_test_result
    connection_test_kind connection_test_message
  )a

  def render(assigns) do
    assigns = assign(assigns, :ops_data_sources_page, page_dto(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-data-sources-component"
        v-component="OpsDataSources"
        page={@ops_data_sources_page}
        v-on:open-register-source={JS.push("open_register_source")}
        v-on:cancel-register-source={JS.push("cancel_register_source")}
        v-on:register-source={JS.push("register_source")}
        v-on:open-change-binding={JS.push("open_change_binding")}
        v-on:cancel-change-binding={JS.push("cancel_change_binding")}
        v-on:change-binding={JS.push("change_binding")}
        v-on:disable-source={JS.push("disable_source")}
        v-on:enable-source={JS.push("enable_source")}
        v-on:reconcile-tsdb-backend={JS.push("reconcile_tsdb_backend")}
        v-on:deprovision-tsdb-backend={JS.push("deprovision_tsdb_backend")}
        v-on:provision-tsdb-backend={JS.push("provision_tsdb_backend")}
        v-on:probe-source={JS.push("probe_source")}
        v-on:rotate-source-credential={JS.push("rotate_source_credential")}
        v-on:retry-deployment-run={JS.push("retry_deployment_run")}
        v-on:requeue-deployment-run={JS.push("requeue_deployment_run")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto(assigns) do
    mission_id = assigns.current_mission.mission_id

    %{
      id: "ops-data-sources-page",
      mode: if(assigns.source_admin?, do: "admin", else: "reader"),
      focus: focus_dto(assigns, mission_id),
      header: header_dto(assigns, mission_id),
      bindings: %{
        heading: "Bindings",
        description: "grouped by logical source and realm",
        empty: "No dashboard source bindings registered.",
        groups: Enum.map(assigns.binding_groups, &binding_group_dto(&1, assigns))
      },
      sources: %{
        heading: "Physical Sources",
        subtitle: "Registered adapter-backed stores",
        empty: "No data sources registered.",
        rows: Enum.map(assigns.source_rows, &source_row_dto(&1, assigns, mission_id))
      },
      deployment_runs: %{
        heading: "Deployment Runs",
        subtitle: "TSDB backend lifecycle jobs",
        empty: "No deployment runs recorded.",
        rows: Enum.map(assigns.deployment_run_rows, &deployment_run_dto(&1, assigns))
      },
      activity: %{
        binding_events:
          event_list_dto(
            "dashboard-data-binding-events",
            "Recent Binding Events",
            "Current projection changes",
            "No binding events recorded.",
            assigns.binding_event_rows
          ),
        source_events:
          event_list_dto(
            "dashboard-data-source-events",
            "Recent Source Events",
            "Physical source descriptor changes",
            "No source events recorded.",
            assigns.source_event_rows
          ),
        health_events:
          event_list_dto(
            "dashboard-source-health-events",
            "Recent Source Health",
            "Source subsystem transitions",
            "No source health events recorded.",
            assigns.source_health_event_rows
          )
      }
    }
    |> maybe_put_admin(assigns)
  end

  defp header_dto(assigns, mission_id) do
    %{
      heading: if(assigns.source_admin?, do: "Data Source Settings", else: "Data Sources"),
      mission_id: mission_id,
      register_link: register_link_dto(assigns.current_scope, mission_id),
      stats: [
        %{label: "sources", value: length(assigns.data_sources)},
        %{label: "bindings", value: length(assigns.data_bindings)},
        %{label: "health", value: length(assigns.source_health_statuses)}
      ],
      readiness_policy: %{
        id: "source-readiness-policy",
        label: "readiness policy",
        policy_id: assigns.source_readiness_policy.policy_id,
        block_source_health: assigns.source_readiness_policy.block_source_health,
        block_freshness: assigns.source_readiness_policy.block_freshness,
        block_connection_test: assigns.source_readiness_policy.block_connection_test,
        connection_summary: "conn #{assigns.source_readiness_policy.block_connection_test}"
      }
    }
  end

  defp register_link_dto(scope, mission_id) do
    if source_admin_eligible?(scope) do
      %{
        id: "register-source-button",
        href: ~p"/missions/#{mission_id}/ops/data-sources/registration/new",
        label: "Register Source",
        icon: "hero-plus"
      }
    end
  end

  defp focus_dto(assigns, mission_id) do
    focus = assigns.source_focus

    %{
      state: focus.state,
      data_source_id: empty(focus.data_source_id),
      source_binding_id: empty(focus.source_binding_id),
      logical_source: empty(focus.logical_source),
      realm: empty(focus.realm),
      scope_kind: empty(focus.scope_kind),
      scope_id: empty(focus.scope_id),
      contact_id: empty(focus.contact_id),
      selected_target: empty(focus.selected_target),
      selected_id: empty(focus.selected_id),
      transport_id: empty(focus.transport_id),
      source_endpoint_id: empty(focus.source_endpoint_id),
      ground_station_id: empty(focus.ground_station_id),
      link_id: empty(focus.link_id),
      source_empty_reason: empty(focus.source_empty_reason),
      requested_source_products: empty(focus.requested_source_products),
      requested_product_families: empty(focus.requested_product_families),
      source_dashboard_id: empty(focus.source_dashboard_id),
      selected_evidence_kind: empty(focus.selected_evidence_kind),
      selected_source_evidence_mode: empty(focus.selected_source_evidence_mode),
      selected_source_evidence_state: empty(focus.selected_source_evidence_state),
      notice: focus_notice_dto(focus),
      remediation:
        remediation_dto(focus, assigns.data_sources, assigns.source_admin?, mission_id),
      resource: resource_dto(focus, assigns.source_focus_resources, mission_id),
      evidence: evidence_dto(focus, mission_id)
    }
  end

  defp focus_notice_dto(%{state: "none"}), do: nil

  defp focus_notice_dto(focus) do
    %{
      id: "source-focus-status",
      icon: SourceFocus.icon(focus),
      title: SourceFocus.title(focus),
      detail: SourceFocus.detail(focus)
    }
  end

  defp remediation_dto(focus, sources, source_admin?, mission_id) do
    case SourceFocusPresentation.remediation(focus, sources) do
      nil ->
        nil

      remediation ->
        %{
          id: "source-focus-remediation",
          kind: remediation.kind,
          title: remediation.title,
          detail: remediation.detail,
          target: remediation.target,
          target_id: empty(remediation.target_id),
          capability_rows:
            Enum.map(remediation.capability_rows, fn row ->
              %{
                key: row.key,
                label: row.label,
                requested: row.requested,
                supported: row.supported
              }
            end),
          candidate_rows:
            Enum.map(remediation.candidate_rows, fn candidate ->
              %{
                data_source_id: candidate.data_source_id,
                compatible: candidate.compatible?,
                status_text: candidate.status_text,
                missing_text: candidate.missing_text,
                reason_text: candidate.reason_text
              }
            end),
          dashboard_return:
            dashboard_return_dto(focus, mission_id, "source-focus-dashboard-return")
        }
        |> maybe_put_optional(:action, remediation_action_dto(remediation, source_admin?))
    end
  end

  defp remediation_action_dto(%{action: :register_source}, true) do
    %{
      kind: "event",
      id: "source-focus-register-source",
      event: "open_register_source",
      payload: %{},
      label: "Register Source",
      icon: "hero-plus"
    }
  end

  defp remediation_action_dto(%{action: :register_source}, false), do: nil

  defp remediation_action_dto(%{action: :review_binding, target_id: target_id}, _source_admin?) do
    %{
      kind: "anchor",
      id: "source-focus-review-binding",
      href: "#source-binding-#{target_id}",
      label: "Review Binding",
      icon: "hero-arrows-right-left"
    }
  end

  defp remediation_action_dto(%{action: :review_source, target_id: target_id}, _source_admin?) do
    %{
      kind: "anchor",
      id: "source-focus-review-source",
      href: "#data-source-#{target_id}",
      label: "Review Source",
      icon: "hero-server-stack"
    }
  end

  defp remediation_action_dto(_remediation, _source_admin?), do: nil

  defp resource_dto(focus, resources, mission_id) do
    focus
    |> SourceFocusResources.build(resources, fn key, value ->
      resource_href(resources, mission_id, key, value)
    end)
    |> case do
      nil ->
        nil

      resource ->
        %{
          id: "source-focus-resource",
          selected_target: empty(resource.selected_target),
          selected_id: empty(resource.selected_id),
          transport_id: empty(resource.transport_id),
          source_endpoint_id: empty(resource.source_endpoint_id),
          ground_station_id: empty(resource.ground_station_id),
          link_id: empty(resource.link_id),
          heading: "Operational resource context",
          rows:
            Enum.map(resource.rows, fn row ->
              %{
                key: row.key,
                label: row.label,
                value: row.value,
                display_value: row.display_value,
                status: row.status,
                status_text: row.status_text,
                href: row.href
              }
            end)
        }
    end
  end

  defp evidence_dto(focus, mission_id) do
    case SourceFocusPresentation.evidence(focus) do
      nil ->
        nil

      evidence ->
        %{
          id: "source-focus-evidence",
          kind: evidence.kind,
          mode: evidence.mode,
          state: evidence.state,
          reason: evidence.reason,
          title: evidence.title,
          detail: evidence.detail,
          dashboard_return:
            dashboard_return_dto(
              focus,
              mission_id,
              "source-focus-evidence-dashboard-return"
            )
        }
    end
  end

  defp dashboard_return_dto(%{source_dashboard_id: dashboard_id} = focus, mission_id, id)
       when is_binary(dashboard_id) and dashboard_id != "" do
    params =
      %{
        "panel" => SourceFocus.return_panel(focus),
        "activity_filter" => SourceFocus.return_activity_filter(focus),
        "activity_event" => SourceFocus.return_activity_event(focus),
        "refresh_readiness" => SourceFocus.return_refresh_readiness(focus)
      }
      |> compact()

    %{
      id: id,
      href: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{params}",
      label: "Return to dashboard readiness",
      icon: "hero-arrow-uturn-left",
      dashboard_id: dashboard_id,
      panel: SourceFocus.return_panel(focus),
      activity_filter: SourceFocus.return_activity_filter(focus),
      activity_event: empty(SourceFocus.return_activity_event(focus))
    }
  end

  defp dashboard_return_dto(_focus, _mission_id, _id), do: nil

  defp resource_href(_resources, mission_id, :transport_id, transport_id) do
    ~p"/missions/#{mission_id}/comms/transports/#{transport_id}"
  end

  defp resource_href(_resources, mission_id, :source_endpoint_id, source_endpoint_id) do
    ~p"/missions/#{mission_id}/comms?#{%{source_endpoint_id: source_endpoint_id}}"
  end

  defp resource_href(
         %{routing_rule: %{routing_rule_id: routing_rule_id}},
         mission_id,
         :link_id,
         _link_id
       ) do
    ~p"/missions/#{mission_id}/comms/routing/#{routing_rule_id}"
  end

  defp resource_href(
         %{ground_station: %{ground_station_id: ground_station_id}},
         mission_id,
         :ground_station_id,
         _ground_station_id
       ) do
    ~p"/missions/#{mission_id}/comms/ground-stations/#{ground_station_id}"
  end

  defp resource_href(_resources, _mission_id, _key, _value), do: nil

  defp binding_group_dto(group, assigns) do
    %{
      id: group.id,
      logical_source_text: group.logical_source_text,
      realm_text: group.realm_text,
      group_status: group.group_status,
      count_label: "#{length(group.rows)} bindings",
      rows: Enum.map(group.rows, &binding_row_dto(&1, assigns))
    }
  end

  defp binding_row_dto(row, assigns) do
    row
    |> Map.take(@binding_row_fields)
    |> Map.put(:binding_id, row.binding.binding_id)
    |> Map.put(:focused, SourceFocus.binding_focused?(assigns.source_focus, row))
    |> maybe_put_change_action(assigns.source_admin?)
  end

  defp maybe_put_change_action(row, false), do: row

  defp maybe_put_change_action(row, true) do
    Map.put(row, :change_action, %{
      id: "change-binding-#{row.binding_id}",
      event: "open_change_binding",
      payload: %{"binding-id" => row.binding_id},
      label: "Change",
      icon: "hero-arrows-right-left"
    })
  end

  defp source_row_dto(row, assigns, mission_id) do
    row
    |> Map.take(@source_row_fields)
    |> Map.put(:focused, SourceFocus.source_focused?(assigns.source_focus, row))
    |> Map.put(:detail_link, %{
      href: ~p"/missions/#{mission_id}/ops/data-sources/#{row.data_source_id}",
      label: row.data_source_id
    })
    |> maybe_put_settings_link(row, assigns, mission_id)
    |> maybe_put_source_actions(row, assigns.source_admin?)
  end

  defp maybe_put_settings_link(dto, row, assigns, mission_id) do
    if source_admin_eligible?(assigns.current_scope) and not assigns.source_admin? do
      Map.put(dto, :settings_link, %{
        id: "source-settings-#{row.data_source_id}",
        href: ~p"/missions/#{mission_id}/ops/data-sources/#{row.data_source_id}/settings",
        label: "Settings",
        icon: "hero-cog-6-tooth"
      })
    else
      dto
    end
  end

  defp maybe_put_source_actions(dto, _row, false), do: dto

  defp maybe_put_source_actions(dto, row, true) do
    actions =
      []
      |> maybe_add_action(
        row.credential_action?,
        source_action(
          "rotate-credential-#{row.data_source_id}",
          "rotate_source_credential",
          %{
            "data-source-id" => row.data_source_id,
            "credentials-ref" => row.credentials_ref
          },
          "Rotate Credential",
          "hero-key",
          "ghost",
          "Rotate this credential reference?"
        )
      )
      |> maybe_add_action(
        row.backend_reconcile_action?,
        source_action(
          "reconcile-backend-#{row.data_source_id}",
          "reconcile_tsdb_backend",
          %{"data-source-id" => row.data_source_id},
          "Reconcile Backend",
          "hero-arrow-path",
          "ghost"
        )
      )
      |> maybe_add_action(
        row.backend_provision_action?,
        source_action(
          "provision-backend-#{row.data_source_id}",
          "provision_tsdb_backend",
          %{"data-source-id" => row.data_source_id},
          "Provision Backend",
          "hero-server-stack",
          "secondary"
        )
      )
      |> maybe_add_action(
        row.backend_deprovision_action?,
        source_action(
          "deprovision-backend-#{row.data_source_id}",
          "deprovision_tsdb_backend",
          %{"data-source-id" => row.data_source_id},
          "Deprovision Backend",
          "hero-trash",
          "danger",
          "Request deprovisioning for this dedicated TSDB backend?"
        )
      )
      |> maybe_add_action(
        row.status_text == "active",
        source_action(
          "probe-source-#{row.data_source_id}",
          "probe_source",
          %{"data-source-id" => row.data_source_id},
          "Probe",
          "hero-arrow-path",
          "ghost"
        )
      )
      |> maybe_add_action(
        row.status_text == "active",
        source_action(
          "disable-source-#{row.data_source_id}",
          "disable_source",
          %{"data-source-id" => row.data_source_id},
          "Disable",
          "hero-pause",
          "danger",
          "Disable this data source?"
        )
      )
      |> maybe_add_action(
        row.enable_action?,
        source_action(
          "enable-source-#{row.data_source_id}",
          "enable_source",
          %{"data-source-id" => row.data_source_id},
          "Enable",
          "hero-play",
          "secondary"
        )
      )

    Map.put(dto, :actions, actions)
  end

  defp source_action(id, event, payload, label, icon, variant, confirm \\ nil) do
    %{
      id: id,
      event: event,
      payload: payload,
      label: label,
      icon: icon,
      variant: variant,
      confirm: confirm
    }
  end

  defp maybe_add_action(actions, true, action), do: actions ++ [action]
  defp maybe_add_action(actions, false, _action), do: actions

  defp deployment_run_dto(row, assigns) do
    row
    |> Map.take(@deployment_run_fields)
    |> maybe_put_deployment_action(assigns.source_admin?)
  end

  defp maybe_put_deployment_action(row, false), do: row

  defp maybe_put_deployment_action(%{status_text: "failed"} = row, true) do
    Map.put(row, :action, %{
      id: "retry-deployment-run-#{row.run_id}",
      event: "retry_deployment_run",
      payload: %{"job-id" => row.job_id},
      label: "Retry",
      icon: "hero-arrow-path"
    })
  end

  defp maybe_put_deployment_action(%{status_text: "provisioning"} = row, true) do
    Map.put(row, :action, %{
      id: "requeue-deployment-run-#{row.run_id}",
      event: "requeue_deployment_run",
      payload: %{"job-id" => row.job_id},
      label: "Requeue",
      icon: "hero-arrow-path"
    })
  end

  defp maybe_put_deployment_action(row, true), do: row

  defp event_list_dto(id, heading, subtitle, empty_message, rows) do
    %{
      id: id,
      heading: heading,
      subtitle: subtitle,
      empty: empty_message,
      rows: Enum.map(rows, &Map.take(&1, @event_row_fields))
    }
  end

  defp maybe_put_admin(page, %{source_admin?: false}), do: page

  defp maybe_put_admin(page, assigns) do
    Map.put(page, :admin, %{
      registration: registration_dto(assigns),
      binding_form: binding_form_dto(assigns)
    })
  end

  defp registration_dto(%{register_source?: false}), do: nil

  defp registration_dto(assigns) do
    %{
      id: "register-source-panel",
      heading: "Register Source",
      description:
        "Source descriptors are scoped to this mission. BYO sources store only a non-secret credential reference.",
      form: %{
        id: "register-source-form",
        values: %{
          data_source_id: form_value(assigns.register_source_form, "data_source_id"),
          logical_source: form_value(assigns.register_source_form, "logical_source"),
          kind: form_value(assigns.register_source_form, "kind"),
          isolation_level: form_value(assigns.register_source_form, "isolation_level"),
          credentials_ref: form_value(assigns.register_source_form, "credentials_ref"),
          credential_provider: form_value(assigns.register_source_form, "credential_provider"),
          endpoint_ref: form_value(assigns.register_source_form, "endpoint_ref"),
          material_env_profile: form_value(assigns.register_source_form, "material_env_profile"),
          http_endpoint_env: form_value(assigns.register_source_form, "http_endpoint_env"),
          storage: form_value(assigns.register_source_form, "storage")
        },
        options: %{
          logical_source: options_dto(SourceRegistration.logical_source_options()),
          kind: options_dto(SourceRegistration.source_kind_options()),
          isolation_level: options_dto(SourceRegistration.source_isolation_options()),
          credential_provider: options_dto(SourceRegistration.credential_provider_options()),
          storage: options_dto(SourceRegistration.source_storage_options())
        },
        error: assigns.register_source_error
      }
    }
  end

  defp binding_form_dto(%{change_binding: nil}), do: nil

  defp binding_form_dto(assigns) do
    %{
      binding_id: assigns.change_binding.binding.binding_id,
      form_id: "change-binding-form-#{assigns.change_binding.binding.binding_id}",
      panel_id: "change-binding-form-panel-#{assigns.change_binding.binding.binding_id}",
      data_source_id: form_value(assigns.change_binding_form, "data_source_id"),
      source_options: options_dto(assigns.change_binding.source_options),
      error: assigns.change_binding_error
    }
  end

  defp options_dto(options) do
    Enum.map(options, fn {label, value} -> %{label: label, value: value} end)
  end

  defp form_value(%Phoenix.HTML.Form{params: params}, key) do
    params
    |> Map.get(key, "")
    |> string_value()
  end

  defp string_value(nil), do: ""
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value), do: to_string(value)

  defp compact(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp maybe_put_optional(map, _key, nil), do: map
  defp maybe_put_optional(map, key, value), do: Map.put(map, key, value)

  defp empty(nil), do: ""
  defp empty(value) when is_binary(value), do: value
  defp empty(value), do: to_string(value)

  defp source_admin_eligible?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end
end
