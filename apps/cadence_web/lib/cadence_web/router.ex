defmodule CadenceWeb.Router do
  use CadenceWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CadenceWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CadenceWeb.Plugs.FetchBrowserCurrentScope
  end

  pipeline :redirect_if_authenticated_scope do
    plug CadenceWeb.Plugs.RedirectIfAuthenticatedScope
  end

  pipeline :require_authenticated_scope do
    plug CadenceWeb.Plugs.RequireAuthenticatedScope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug CadenceWeb.Plugs.FetchCurrentScope
    plug CadenceWeb.Plugs.RequireCurrentScope
  end

  scope "/", CadenceWeb do
    pipe_through [:browser, :redirect_if_authenticated_scope]

    live_session :auth, layout: {CadenceWeb.Layouts, :auth} do
      live "/sign-in", UserSessionLive, :new
    end

    post "/sign-in", UserSessionController, :create
  end

  scope "/", CadenceWeb do
    pipe_through :browser

    get "/invitations/:invitation_token", OrganizationInvitationController, :show
    post "/invitations/:invitation_token", OrganizationInvitationController, :update
  end

  scope "/", CadenceWeb do
    pipe_through [:browser, :require_authenticated_scope]

    delete "/session", UserSessionController, :delete
    get "/no-organization", NoOrganizationController, :show

    live_session :organization,
      on_mount: [{CadenceWeb.OrganizationAuth, :require_organization_scope}],
      layout: {CadenceWeb.Layouts, :sidebar} do
      live "/", OrganizationHomeLive, :show
      live "/missions", MissionListLive, :index
      live "/missions/new", MissionNewLive, :new
    end

    live_session :mission,
      on_mount: [
        {CadenceWeb.OrganizationAuth, :require_organization_scope},
        {CadenceWeb.MissionAuth, :load_mission}
      ],
      layout: {CadenceWeb.Layouts, :mission_sidebar} do
      live "/missions/:mission_id", MissionShowLive, :show
    end

    live_session :admin,
      on_mount: [{CadenceWeb.AdminAuth, :require_platform_admin}],
      layout: {CadenceWeb.Layouts, :sidebar} do
      live "/admin", AdminHomeLive, :index
      live "/admin/organizations", AdminOrganizationListLive, :index
      live "/admin/organizations/new", AdminOrganizationNewLive, :new
      live "/admin/organizations/:org_id", AdminOrganizationShowLive, :show
      live "/admin/organizations/:org_id/invite", AdminOrganizationInviteLive, :invite
    end
  end

  scope "/api", CadenceWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/bootstrap_admin/login", BootstrapAdminSessionController, :create
  end

  scope "/api", CadenceWeb do
    pipe_through [:api, :authenticated_api]

    get "/current_scope", CurrentScopeController, :show
    post "/bootstrap", BootstrapController, :create

    scope "/organizations/:organization_id" do
      get "/", OrganizationController, :show

      get "/missions", MissionController, :index
      post "/missions", MissionController, :create
      get "/missions/:mission_id", MissionController, :show

      get "/service_identities", ServiceIdentityController, :index
      post "/service_identities", ServiceIdentityController, :create

      scope "/missions/:mission_id" do
        get "/mission_health", MissionHealthController, :show
        get "/mission_events", MissionEventController, :index
        get "/telemetry/latest", TelemetryController, :latest_values
        get "/telemetry/points/:point_id/latest", TelemetryController, :latest_value
        get "/telemetry/points/:point_id/history", TelemetryController, :history
        post "/dev/space_packets", DevSpacePacketController, :create
        post "/dev/tm_frames", DevTMFrameController, :create
        get "/catalog/importers", CatalogImporterController, :index
        get "/catalog_artifacts", CatalogArtifactController, :index
        post "/catalog_artifacts", CatalogArtifactController, :create
        get "/catalog_artifacts/:artifact_id", CatalogArtifactController, :show
        get "/catalog_import_runs", CatalogImportRunController, :index
        post "/catalog_import_runs", CatalogImportRunController, :create
        get "/catalog_import_runs/:import_run_id", CatalogImportRunController, :show
        get "/catalog_telemetry_snapshots", CatalogTelemetrySnapshotController, :index
        get "/catalog_telemetry_snapshots/:snapshot_id", CatalogTelemetrySnapshotController, :show
        get "/catalog_command_snapshots", CatalogCommandSnapshotController, :index
        get "/catalog_command_snapshots/:snapshot_id", CatalogCommandSnapshotController, :show

        get "/catalog_command_snapshots/:snapshot_id/compile",
            CatalogCommandSnapshotController,
            :compile

        get "/catalog_telemetry_snapshots/:snapshot_id/recompile",
            CatalogTelemetrySnapshotController,
            :recompile

        get "/catalog_telemetry_snapshots/:snapshot_id/runtime_diff",
            CatalogTelemetrySnapshotController,
            :runtime_diff

        post "/catalog_telemetry_snapshots/:snapshot_id/materialize_runtime",
             CatalogTelemetrySnapshotController,
             :materialize_runtime

        get "/spacecraft", SpacecraftController, :index
        post "/spacecraft", SpacecraftController, :create
        get "/spacecraft/:spacecraft_id", SpacecraftController, :show
        get "/provider_profiles", ProviderProfileController, :index
        post "/provider_profiles", ProviderProfileController, :create

        get "/provider_profiles/:provider_profile_id/versions",
            ProviderProfileController,
            :versions

        get "/provider_profiles/:provider_profile_id/versions/:version",
            ProviderProfileController,
            :show_version

        get "/provider_profiles/:provider_profile_id", ProviderProfileController, :show
        patch "/provider_profiles/:provider_profile_id", ProviderProfileController, :update
        delete "/provider_profiles/:provider_profile_id", ProviderProfileController, :delete
        get "/transport_profiles", TransportProfileController, :index
        post "/transport_profiles", TransportProfileController, :create

        get "/transport_profiles/:transport_profile_id/versions",
            TransportProfileController,
            :versions

        get "/transport_profiles/:transport_profile_id/versions/:version",
            TransportProfileController,
            :show_version

        get "/transport_profiles/:transport_profile_id", TransportProfileController, :show
        patch "/transport_profiles/:transport_profile_id", TransportProfileController, :update
        delete "/transport_profiles/:transport_profile_id", TransportProfileController, :delete
        get "/path_templates", PathTemplateController, :index
        post "/path_templates", PathTemplateController, :create
        get "/path_templates/:path_template_id/versions", PathTemplateController, :versions

        get "/path_templates/:path_template_id/versions/:version",
            PathTemplateController,
            :show_version

        get "/path_templates/:path_template_id", PathTemplateController, :show
        patch "/path_templates/:path_template_id", PathTemplateController, :update
        delete "/path_templates/:path_template_id", PathTemplateController, :delete
        get "/spacecraft/:spacecraft_id/source_endpoints", SourceEndpointController, :index
        post "/spacecraft/:spacecraft_id/source_endpoints", SourceEndpointController, :create

        get "/source_endpoints", SourceEndpointController, :index
        post "/source_endpoints", SourceEndpointController, :create
        get "/source_endpoints/:source_endpoint_id", SourceEndpointController, :show

        get "/command_stages", CommandStageController, :index
        post "/command_stages", CommandStageController, :create
        get "/command_stages/:command_stage_id", CommandStageController, :show
        patch "/command_stages/:command_stage_id", CommandStageController, :update
        post "/command_stages/:command_stage_id/submit", CommandStageController, :submit

        get "/command_stages/:command_stage_id/items", StagedCommandItemController, :index
        post "/command_stages/:command_stage_id/items", StagedCommandItemController, :create

        get "/staged_command_items/:staged_command_item_id", StagedCommandItemController, :show

        patch "/staged_command_items/:staged_command_item_id",
              StagedCommandItemController,
              :update

        get "/command_requests", CommandRequestController, :index
        post "/command_requests", CommandRequestController, :create
        get "/command_requests/:command_request_id", CommandRequestController, :show
        post "/command_requests/:command_request_id/approve", CommandRequestController, :approve
        post "/command_requests/:command_request_id/reject", CommandRequestController, :reject
        post "/command_requests/:command_request_id/enqueue", CommandRequestController, :enqueue

        get "/command_approvals", CommandApprovalController, :index
        get "/command_approvals/:command_approval_id", CommandApprovalController, :show

        get "/command_queue_entries", CommandQueueEntryController, :index
        get "/command_queue_entries/:command_queue_entry_id", CommandQueueEntryController, :show

        post "/command_queue_entries/:command_queue_entry_id/release",
             CommandQueueEntryController,
             :release

        get "/command_release_attempts", CommandReleaseAttemptController, :index

        get "/command_release_attempts/:command_release_attempt_id",
            CommandReleaseAttemptController,
            :show

        get "/command_verifier_instances", CommandVerifierInstanceController, :index

        get "/command_verifier_instances/:command_verifier_instance_id",
            CommandVerifierInstanceController,
            :show

        get "/scheduled_contacts", ScheduledContactController, :index
        post "/scheduled_contacts", ScheduledContactController, :create
        get "/scheduled_contacts/:scheduled_contact_id", ScheduledContactController, :show

        post "/scheduled_contacts/:scheduled_contact_id/realize",
             ScheduledContactController,
             :realize

        post "/scheduled_contacts/:scheduled_contact_id/cancel",
             ScheduledContactController,
             :cancel

        get "/realized_contacts", RealizedContactController, :index
        get "/realized_contacts/:realized_contact_id/runtime", RealizedContactController, :runtime

        get "/realized_contacts/:realized_contact_id/paths/:path_id/runtime",
            RealizedContactController,
            :path_runtime

        get "/realized_contacts/:realized_contact_id", RealizedContactController, :show

        post "/realized_contacts/:realized_contact_id/end_early",
             RealizedContactController,
             :end_early

        get "/contact_actions", ContactActionController, :index

        get "/packet_definitions", PacketDefinitionController, :index
        post "/packet_definitions", PacketDefinitionController, :create

        post "/binding_sets", BindingSetController, :create
        get "/binding_sets/:binding_set_id/versions/:version", BindingSetController, :show

        post "/activations", ActivationController, :create
        get "/activations/active", ActivationController, :show
      end
    end
  end
end
