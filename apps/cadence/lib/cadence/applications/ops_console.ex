defmodule Cadence.Applications.OpsConsole do
  @moduledoc "The first-party contribution boundary for the federated Ops Console."

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition,
    SurfaceQueryContribution
  }

  @identity %{
    application_key: "ops_console",
    application_version: 1,
    package_id: "cadence.ops_console",
    package_version: 1,
    surface_version: 1,
    release_id: "ops-console-v1",
    remote_name: "cadence_ops_console",
    manifest_path: "/assets/application-host/ops-console/mf-manifest.json",
    exposed_module: "./Application"
  }

  @surface_specs [
    %{
      id: "workspace",
      purpose: :overview,
      placement: :application_workspace,
      label: "Ops Console",
      order: 10,
      query_id: "cadence.ops.workspace",
      path: "/missions/:mission_id/ops",
      actions: []
    },
    %{
      id: "ops",
      purpose: :operations,
      placement: :ops_workspace,
      label: "Operations",
      order: 10,
      query_id: "cadence.ops.console",
      path: "/missions/:mission_id/ops",
      actions: [
        "validate",
        "save",
        "filter",
        "refresh",
        "select",
        "open_data_link",
        "open_evidence",
        "set_chart_time_range"
      ]
    },
    %{
      id: "contact_requirement_list",
      purpose: :collection,
      label: "Contact Requirements",
      path: "/missions/:mission_id/ops/requirements",
      actions: []
    },
    %{
      id: "contact_requirement_new",
      purpose: :configuration,
      label: "New Contact Requirement",
      path: "/missions/:mission_id/ops/requirements/new",
      actions: ["validate", "save"]
    },
    %{
      id: "contact_requirement_show",
      purpose: :subject_detail,
      label: "Contact Requirement",
      path: "/missions/:mission_id/ops/requirements/:contact_requirement_id",
      actions: ["plan", "toggle-opportunity", "create-plan"]
    },
    %{
      id: "contact_requirement_template",
      purpose: :configuration,
      label: "Requirement Templates",
      path: "/missions/:mission_id/ops/requirement-templates",
      actions: [
        "validate-template",
        "create-template",
        "pause-template",
        "activate-template",
        "close-template"
      ]
    },
    %{
      id: "contact_schedule",
      purpose: :operations,
      label: "Contact Schedule",
      path: "/missions/:mission_id/ops/contacts",
      actions: ["validate", "search", "reserve", "cancel"]
    },
    %{
      id: "contact_plan_show",
      purpose: :subject_detail,
      label: "Contact Plan",
      path: "/missions/:mission_id/ops/plans/:contact_plan_id",
      actions: ["submit-plan", "approve-plan", "reject-plan", "execute-plan"]
    },
    %{
      id: "contact_detail",
      purpose: :subject_detail,
      label: "Contact Detail",
      path: "/missions/:mission_id/ops/contacts/:provider_reservation_id",
      actions: [
        "approve-provider-change",
        "reject-provider-change",
        "acknowledge-provider-change"
      ]
    },
    %{
      id: "contact_record",
      purpose: :subject_detail,
      label: "Contact Record",
      path: "/missions/:mission_id/ops/contacts/records/:contact_id",
      actions: []
    },
    %{
      id: "dashboard_directory",
      purpose: :collection,
      label: "Dashboards",
      path: "/missions/:mission_id/ops/dashboards",
      actions: ["filter_dashboards", "toggle_dashboard_star", "restore_dashboard"]
    },
    %{
      id: "dashboard_show",
      purpose: :subject_detail,
      label: "Dashboard",
      path: "/missions/:mission_id/ops/dashboards/:dashboard_id",
      subject_param: "dashboard_id",
      query_params: [
        "dashboard_id",
        "panel",
        "activity_filter",
        "activity_event",
        "selected_publish_issue",
        "selected_time",
        "time_mode",
        "time_axis",
        "from",
        "to",
        "limit_mode",
        "replay_run_id",
        "selection_view",
        "selected_widget",
        "selected_target",
        "selected_id",
        "selected_placement",
        "selected_data_view",
        "selected_scope_kind",
        "selected_scope_id",
        "selected_resource_id",
        "selected_spacecraft_id",
        "selected_contact_id",
        "selected_transport_id",
        "selected_source_endpoint_id",
        "selected_ground_station_id",
        "selected_scope_link_id",
        "realm",
        "data_source_id",
        "source_binding_id"
      ],
      actions: []
    },
    %{
      id: "dashboard_editor",
      purpose: :configuration,
      label: "Dashboard Editor",
      path: "/missions/:mission_id/ops/dashboards/:dashboard_id/edit",
      subject_param: "dashboard_id",
      query_params: ["dashboard_id"],
      actions: [
        "layout_changed",
        "validate_dashboard_section",
        "save_dashboard_section",
        "remove_dashboard_section",
        "move_dashboard_section",
        "preview_widget_binding",
        "validate_widget",
        "save_widget",
        "remove_widget",
        "rename",
        "archive_dashboard",
        "publish_dashboard",
        "publish_dashboard_version",
        "save_runtime_defaults",
        "restore_version_as_draft",
        "save_editor",
        "review_editor",
        "discard_editor",
        "reload_editor"
      ]
    },
    %{
      id: "dashboard_activity",
      purpose: :activity,
      label: "Dashboard Activity",
      path: "/missions/:mission_id/ops/dashboards/:dashboard_id/activity",
      subject_param: "dashboard_id",
      query_params: ["dashboard_id", "version", "selected_publish_issue"],
      actions: ["publish_version", "restore_version"]
    },
    %{
      id: "dashboard_new",
      purpose: :configuration,
      label: "New Dashboard",
      path: "/missions/:mission_id/ops/dashboards/new",
      actions: ["validate", "save"]
    },
    %{
      id: "dashboard_library",
      purpose: :collection,
      label: "Dashboard Library",
      path: "/missions/:mission_id/ops/dashboards/library",
      actions: ["stage-library-item", "create-library-item", "add-library-version"]
    },
    %{
      id: "dashboard_playlists",
      purpose: :collection,
      label: "Dashboard Playlists",
      path: "/missions/:mission_id/ops/dashboards/playlists",
      actions: ["create-playlist"]
    },
    %{
      id: "dashboard_playlist_present",
      purpose: :operations,
      label: "Present Playlist",
      path: "/missions/:mission_id/ops/dashboards/playlists/:playlist_id/present",
      actions: ["next-dashboard"]
    },
    %{
      id: "dashboard_settings",
      purpose: :configuration,
      label: "Dashboard Settings",
      path: "/missions/:mission_id/ops/dashboards/:dashboard_id/settings",
      actions: [
        "validate-settings",
        "save-settings",
        "create-share",
        "revoke-share",
        "create-snapshot",
        "archive-dashboard"
      ]
    },
    %{
      id: "dashboard_share",
      purpose: :subject_detail,
      label: "Dashboard Share",
      path: "/missions/:mission_id/ops/dashboard-shares/:share_id",
      actions: []
    },
    %{
      id: "dashboard_snapshot",
      purpose: :subject_detail,
      label: "Dashboard Snapshot",
      path: "/missions/:mission_id/ops/dashboard-snapshots/:snapshot_id",
      actions: []
    },
    %{
      id: "dashboard_diagnostics",
      purpose: :activity,
      label: "Dashboard Diagnostics",
      path: "/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics",
      actions: []
    },
    %{
      id: "fleet_planning",
      purpose: :operations,
      label: "Fleet Planning",
      path: "/missions/:mission_id/ops/planning",
      actions: ["refresh-planning"]
    },
    %{
      id: "fleet_planning_new",
      purpose: :configuration,
      label: "New Fleet Run",
      path: "/missions/:mission_id/ops/planning/new",
      actions: ["validate-fleet-run", "create-fleet-run"]
    },
    %{
      id: "fleet_planning_policy",
      purpose: :configuration,
      label: "Fleet Planning Policy",
      path: "/missions/:mission_id/ops/planning/policy",
      actions: [
        "validate-policy",
        "save-policy",
        "approve-policy",
        "validate-grant",
        "issue-grant",
        "revoke-grant"
      ]
    },
    %{
      id: "fleet_planning_run",
      purpose: :subject_detail,
      label: "Fleet Planning Run",
      path: "/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id",
      actions: ["refresh-fleet-run", "repair-fleet-run"]
    },
    %{
      id: "activation_requests",
      purpose: :operations,
      label: "Activation Requests",
      path: "/missions/:mission_id/ops/activations",
      actions: ["review", "decide"]
    },
    %{
      id: "commands",
      purpose: :operations,
      label: "Commands",
      path: "/missions/:mission_id/ops/commands",
      actions: ~w(filter reset_filters follow_command clear_command_focus)
    },
    %{
      id: "telemetry_explore",
      purpose: :operations,
      label: "Telemetry Explore",
      path: "/missions/:mission_id/ops/explore",
      actions: ["apply_filters", "apply_question", "add_to_dashboard", "clear_selected_sample"]
    },
    %{
      id: "data_operations",
      purpose: :operations,
      label: "Data Operations",
      path: "/missions/:mission_id/ops/data-operations",
      actions: [
        "validate-request",
        "record-historical-workflow-request",
        "transition-group",
        "retry-group",
        "request-correction"
      ]
    },
    %{
      id: "data_operations_manage",
      purpose: :operations,
      label: "Manage Data Operations",
      path: "/missions/:mission_id/ops/data-operations/manage",
      query_params: ["group"],
      actions: [
        "validate-request",
        "record-historical-workflow-request",
        "transition-group",
        "retry-group",
        "request-correction"
      ]
    },
    %{
      id: "data_sources",
      purpose: :configuration,
      label: "Data Sources",
      path: "/missions/:mission_id/ops/data-sources",
      actions: [
        "open-register-source",
        "cancel-register-source",
        "register-source",
        "open-change-binding",
        "cancel-change-binding",
        "change-binding",
        "disable-source",
        "enable-source",
        "reconcile-tsdb-backend",
        "deprovision-tsdb-backend",
        "provision-tsdb-backend",
        "probe-source",
        "rotate-source-credential",
        "retry-deployment-run",
        "requeue-deployment-run"
      ]
    },
    %{
      id: "data_source_registration",
      purpose: :configuration,
      label: "Register Data Source",
      path: "/missions/:mission_id/ops/data-sources/registration/new",
      query_params: [],
      actions: ["register-source"]
    },
    %{
      id: "data_source_settings",
      purpose: :configuration,
      label: "Data Source Settings",
      path: "/missions/:mission_id/ops/data-sources/:data_source_id/settings",
      subject_param: "data_source_id",
      query_params: ["data_source_id"],
      actions: [
        "change-binding",
        "disable-source",
        "enable-source",
        "reconcile-tsdb-backend",
        "deprovision-tsdb-backend",
        "provision-tsdb-backend",
        "probe-source",
        "rotate-source-credential",
        "retry-deployment-run",
        "requeue-deployment-run"
      ]
    },
    %{
      id: "alarms",
      purpose: :operations,
      label: "Alarms",
      path: "/missions/:mission_id/ops/alarms",
      actions: ~w(filter reset_filters)
    },
    %{
      id: "timeline",
      purpose: :activity,
      label: "Timeline",
      path: "/missions/:mission_id/ops/timeline",
      actions: ~w(apply_timeline_filters clear_timeline_selection)
    }
  ]

  @ops_actions @surface_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq()

  # Exact complement of the composed provider bindings. Empty entries are
  # intentional: every declared surface participates in the partition.
  @residual_action_ledger %{
    "workspace" => [],
    "ops" => [
      "validate",
      "save",
      "filter",
      "refresh",
      "select",
      "open_data_link",
      "open_evidence",
      "set_chart_time_range"
    ],
    "contact_requirement_list" => [],
    "contact_requirement_new" => [],
    "contact_requirement_show" => ["toggle-opportunity"],
    "contact_requirement_template" => [],
    "contact_schedule" => [],
    "contact_plan_show" => [],
    "contact_detail" => [],
    "contact_record" => [],
    "dashboard_directory" => [],
    "dashboard_show" => [],
    "dashboard_editor" => [],
    "dashboard_activity" => [],
    "dashboard_new" => [],
    "dashboard_library" => [],
    "dashboard_playlists" => [],
    "dashboard_playlist_present" => [],
    "dashboard_settings" => [],
    "dashboard_share" => [],
    "dashboard_snapshot" => [],
    "dashboard_diagnostics" => [],
    "fleet_planning" => [],
    "fleet_planning_new" => ["validate-fleet-run"],
    "fleet_planning_policy" => ["validate-policy", "validate-grant"],
    "fleet_planning_run" => [],
    "activation_requests" => ["review"],
    "commands" => ["filter", "reset_filters", "follow_command", "clear_command_focus"],
    "telemetry_explore" => [
      "apply_filters",
      "apply_question",
      "add_to_dashboard",
      "clear_selected_sample"
    ],
    "data_operations" => [],
    "data_operations_manage" => [],
    "data_sources" => [
      "open-register-source",
      "cancel-register-source",
      "open-change-binding",
      "cancel-change-binding"
    ],
    "data_source_registration" => [],
    "data_source_settings" => [],
    "alarms" => [],
    "timeline" => []
  }

  @former_liveview_event_contracts %{
    "dashboard_show" => ~w(
      context_search set_context clear_context set_runtime_context resume_live set_time_preset
      set_chart_time_range shift_time_range zoom_out_time_range time_quick_search time_recents_loaded
      pause_at_selected_time scrub_replay_to_selection clear_data_selection save_comparison_preset
      apply_comparison_preset delete_comparison_preset toggle_comparison_inspector
      close_comparison_inspector request_comparison_review resolve_comparison_review
      apply_comparison_review_bulk_decision capture_dashboard_health_snapshot toggle_edit
      layout_changed open_add_widget open_dashboard_sections edit_dashboard_section
      validate_dashboard_section save_dashboard_section remove_dashboard_section move_dashboard_section
      open_widget_config open_rename open_versions refresh_publish_readiness set_activity_filter
      select_activity_event open_review_activity select_review_placement open_diagnostics
      open_widget_inspector open_historical_workflow_request open_comparison_review_workflow_request
      open_evidence open_data_link record_historical_workflow_stage record_historical_workflow_group_stage
      record_historical_workflow_request record_corrected_historical_workflow_request
      record_late_data_policy_decision apply_revision_decision retry_historical_workflow_job
      inspect_stale_historical_workflow_replacement_job inspect_missing_historical_workflow_replacement_job
      requeue_stale_historical_workflow_replacement_job retry_historical_workflow_group_failed_jobs
      close_panel validate_widget pick_point preview_widget_binding save_widget remove_widget rename
      archive_dashboard publish_dashboard publish_dashboard_version save_runtime_defaults
      restore_version_as_draft save_editor review_editor discard_editor reload_editor
    ),
    "dashboard_editor" => ~w(
      context_search set_context clear_context set_runtime_context resume_live set_time_preset
      set_chart_time_range shift_time_range zoom_out_time_range time_quick_search time_recents_loaded
      pause_at_selected_time scrub_replay_to_selection clear_data_selection save_comparison_preset
      apply_comparison_preset delete_comparison_preset toggle_comparison_inspector
      close_comparison_inspector request_comparison_review resolve_comparison_review
      apply_comparison_review_bulk_decision capture_dashboard_health_snapshot toggle_edit layout_changed
      open_add_widget open_dashboard_sections edit_dashboard_section validate_dashboard_section
      save_dashboard_section remove_dashboard_section move_dashboard_section open_widget_config open_rename
      open_versions refresh_publish_readiness set_activity_filter select_activity_event open_review_activity
      select_review_placement open_diagnostics open_widget_inspector open_historical_workflow_request
      open_comparison_review_workflow_request open_evidence open_data_link record_historical_workflow_stage
      record_historical_workflow_group_stage record_historical_workflow_request
      record_corrected_historical_workflow_request record_late_data_policy_decision apply_revision_decision
      retry_historical_workflow_job inspect_stale_historical_workflow_replacement_job
      inspect_missing_historical_workflow_replacement_job requeue_stale_historical_workflow_replacement_job
      retry_historical_workflow_group_failed_jobs close_panel validate_widget pick_point
      preview_widget_binding save_widget remove_widget rename archive_dashboard publish_dashboard
      publish_dashboard_version save_runtime_defaults restore_version_as_draft save_editor review_editor
      discard_editor reload_editor
    ),
    "dashboard_activity" => ~w(refresh_publish_readiness publish_version restore_version),
    "data_operations_manage" => ~w(
      validate_request record_historical_workflow_request transition_group retry_group request_correction
    ),
    "data_source_registration" => ~w(
      open_register_source cancel_register_source register_source open_change_binding cancel_change_binding
      change_binding disable_source enable_source reconcile_tsdb_backend deprovision_tsdb_backend
      provision_tsdb_backend probe_source rotate_source_credential retry_deployment_run requeue_deployment_run
    ),
    "data_source_settings" => ~w(
      open_register_source cancel_register_source register_source open_change_binding cancel_change_binding
      change_binding disable_source enable_source reconcile_tsdb_backend deprovision_tsdb_backend
      provision_tsdb_backend probe_source rotate_source_credential retry_deployment_run requeue_deployment_run
    )
  }

  @deep_route_interaction_ledger %{
    "dashboard_show" => %{
      host_actions: [],
      navigation: ["open_dashboard_activity", "open_dashboard_editor", "open_dashboard_settings"],
      phoenix_events: [],
      former_liveview_events: @former_liveview_event_contracts["dashboard_show"]
    },
    "dashboard_editor" => %{
      host_actions:
        Enum.map(
          @surface_specs |> Enum.find(&(&1.id == "dashboard_editor")) |> Map.fetch!(:actions),
          & &1
        ),
      navigation: ["open_dashboard_activity", "open_dashboard_settings"],
      phoenix_events: [],
      former_liveview_events: @former_liveview_event_contracts["dashboard_editor"]
    },
    "dashboard_activity" => %{
      host_actions: ["publish_version", "restore_version"],
      navigation: ["open_dashboard_viewer", "open_dashboard_editor"],
      phoenix_events: [],
      former_liveview_events: @former_liveview_event_contracts["dashboard_activity"]
    },
    "data_source_registration" => %{
      host_actions: ["register-source"],
      navigation: ["open_data_sources"],
      phoenix_events: [],
      former_liveview_events: @former_liveview_event_contracts["data_source_registration"]
    },
    "data_source_settings" => %{
      host_actions: [
        "change-binding",
        "disable-source",
        "enable-source",
        "reconcile-tsdb-backend",
        "deprovision-tsdb-backend",
        "provision-tsdb-backend",
        "probe-source",
        "rotate-source-credential",
        "retry-deployment-run",
        "requeue-deployment-run"
      ],
      navigation: ["open_data_sources", "open_data_source_settings"],
      phoenix_events: [],
      former_liveview_events: @former_liveview_event_contracts["data_source_settings"]
    },
    "data_operations_manage" => %{
      host_actions: [
        "validate-request",
        "record-historical-workflow-request",
        "transition-group",
        "retry-group",
        "request-correction"
      ],
      navigation: ["open_data_operations"],
      phoenix_events: [],
      former_liveview_events: @former_liveview_event_contracts["data_operations_manage"]
    }
  }

  @spec identity() :: map()
  def identity, do: @identity

  @spec surface_ids() :: [binary()]
  def surface_ids, do: Enum.map(@surface_specs, & &1.id)

  def surface_specs, do: @surface_specs

  @spec action_ids() :: [binary()]
  def action_ids, do: @ops_actions

  @spec surface_action_pairs() :: [{binary(), binary()}]
  def surface_action_pairs do
    Enum.flat_map(@surface_specs, fn spec -> Enum.map(spec.actions, &{spec.id, &1}) end)
  end

  @spec residual_action_ledger() :: %{binary() => [binary()]}
  def residual_action_ledger, do: @residual_action_ledger

  @spec deep_route_interaction_ledger() :: %{binary() => map()}
  def deep_route_interaction_ledger, do: @deep_route_interaction_ledger

  @spec former_liveview_event_contracts() :: %{binary() => [binary()]}
  def former_liveview_event_contracts, do: @former_liveview_event_contracts

  @spec surface_query_contract(binary()) ::
          {:ok, %{subject_param: binary() | nil, query_params: [binary()]}} | :error
  def surface_query_contract(surface_id) when is_binary(surface_id) do
    case Enum.find(@surface_specs, &(&1.id == surface_id)) do
      nil ->
        :error

      spec ->
        {:ok,
         %{
           subject_param: Map.get(spec, :subject_param),
           query_params: Map.get(spec, :query_params, [])
         }}
    end
  end

  @spec route_action_completion() :: {:complete, 0} | {:residual, non_neg_integer()}
  def route_action_completion do
    residual_count =
      @residual_action_ledger
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> length()

    if residual_count == 0, do: {:complete, 0}, else: {:residual, residual_count}
  end

  @spec application_key() :: binary()
  def application_key, do: @identity.application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.OpsConsole.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    Enum.map(@surface_specs, fn spec ->
      %SurfaceQueryContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        query_id: Map.get(spec, :query_id, "cadence.ops.#{spec.id}"),
        query_version: @identity.surface_version,
        provider: Cadence.Reads.ApplicationSurfaces.OpsConsole
      }
    end)
  end

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    Enum.map(@surface_specs, fn spec ->
      %ReleaseContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        surface_id: spec.id,
        surface_version: @identity.surface_version,
        federation: :module_federation,
        release_id: @identity.release_id,
        remote_name: @identity.remote_name,
        manifest_path: @identity.manifest_path,
        exposed_module: @identity.exposed_module
      }
    end)
  end

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @identity.package_id,
        package_version: @identity.package_version
      }
    ]
  end

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Ops Console",
      description: "Mission operations, dashboard runtime, evidence, and control surfaces.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      actions: action_definitions(),
      surfaces: Enum.map(@surface_specs, &surface_definition/1)
    }
  end

  defp surface_definition(spec) do
    %SurfaceDefinition{
      surface_id: spec.id,
      version: @identity.surface_version,
      purpose: spec.purpose,
      scope: :mission,
      placement: Map.get(spec, :placement, :ops_workspace),
      navigation: %{label: spec.label, order: Map.get(spec, :order, 10), fallback_path: spec.path},
      subject_contract: subject_contract(spec),
      data_contract: %{
        query_id: Map.get(spec, :query_id, "cadence.ops.#{spec.id}"),
        version: @identity.surface_version
      },
      actions: spec.actions,
      refresh: if(spec.id in ["workspace", "ops"], do: :static, else: :after_action),
      renderer: {:trusted, "cadence.ops.console"}
    }
  end

  defp subject_contract(%{subject_param: subject_param} = spec) when is_binary(subject_param) do
    %{schema_id: "cadence.ops_console.#{spec.id}.subject", version: 1}
  end

  defp subject_contract(_spec), do: nil

  defp action_definitions do
    Enum.map(@ops_actions, fn action_id ->
      %ActionDefinition{
        action_id: action_id,
        version: @identity.application_version,
        intent: :operation,
        scope: :mission,
        input_contract: %{schema_id: "cadence.ops_console.#{action_id}.input", version: 1},
        result_contract: %{schema_id: "cadence.ops_console.#{action_id}.result", version: 1},
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        concurrency: %{strategy: :expected_version}
      }
    end)
  end
end
