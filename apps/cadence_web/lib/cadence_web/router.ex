defmodule CadenceWeb.Router do
  use CadenceWeb, :router

  pipeline :browser do
    plug(CadenceWeb.Plugs.BrowserAccepts)
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {CadenceWeb.Layouts, :root})
    plug(CadenceWeb.Plugs.ApplicationHostCSRF)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(CadenceWeb.Plugs.FetchBrowserCurrentScope)
    plug(CadenceWeb.Plugs.AssignUserMenuContext)
  end

  pipeline :redirect_if_authenticated_scope do
    plug(CadenceWeb.Plugs.RedirectIfAuthenticatedScope)
  end

  pipeline :require_authenticated_scope do
    plug(CadenceWeb.Plugs.RequireAuthenticatedScope)
  end

  pipeline :require_authenticated_user do
    plug(CadenceWeb.Plugs.RequireAuthenticatedScope)
  end

  pipeline :application_host_json do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
    plug(CadenceWeb.Plugs.FetchBrowserCurrentScope)
    plug(CadenceWeb.Plugs.RequireApplicationHostScope)
    plug(CadenceWeb.Plugs.ApplicationHostSession)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :frontend_release_publisher do
    plug(CadenceWeb.Plugs.FrontendReleasePublisher)
  end

  pipeline :authenticated_api do
    plug(CadenceWeb.Plugs.FetchCurrentScope)
    plug(CadenceWeb.Plugs.RequireCurrentScope)
  end

  pipeline :frontend_release_artifact do
    plug(:put_secure_browser_headers)
  end

  scope "/", CadenceWeb do
    pipe_through(:frontend_release_artifact)

    get(
      "/releases/:application_id/:release_id/artifacts/*artifact_path",
      FrontendReleaseArtifactController,
      :show
    )
  end

  scope "/", CadenceWeb do
    pipe_through([:browser, :redirect_if_authenticated_scope])

    live_session :auth, layout: {CadenceWeb.Layouts, :auth} do
      live("/sign-in", UserSessionLive, :new)
    end

    post("/sign-in", UserSessionController, :create)
  end

  scope "/", CadenceWeb do
    pipe_through(:browser)

    get("/invitations/:invitation_token", OrganizationInvitationController, :show)
    post("/invitations/:invitation_token", OrganizationInvitationController, :update)
  end

  scope "/", CadenceWeb do
    pipe_through([:browser, :require_authenticated_scope])

    delete("/session", UserSessionController, :delete)
    put("/session/organization", UserSessionController, :update)
    get("/admin-mode", AdminModeController, :new)
    post("/admin-mode", AdminModeController, :create)
    delete("/admin-mode", AdminModeController, :delete)
    get("/no-organization", NoOrganizationController, :show)

    get(
      "/missions/:mission_id/catalog/artifacts/:artifact_id/download",
      CatalogArtifactDownloadController,
      :show
    )

    get(
      "/missions/:mission_id/applications/:application_key/federated",
      ApplicationHostController,
      :federated
    )

    get(
      "/missions/:mission_id/applications/:application_key/:surface_id/federated",
      ApplicationHostController,
      :federated
    )

    get(
      "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/federated",
      ApplicationHostController,
      :federated
    )

    get(
      "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id/federated",
      ApplicationHostController,
      :federated
    )

    # These shells stay in the authenticated browser scope so the Phoenix
    # host can establish organization, user, and admin context from the
    # current session without inventing a mission resource.
    get(
      "/applications/:application_key/federated",
      ApplicationHostController,
      :organization_federated
    )

    get(
      "/applications/:application_key/:surface_id/federated",
      ApplicationHostController,
      :organization_federated
    )

    get(
      "/account/applications/:application_key/federated",
      ApplicationHostController,
      :user_federated
    )

    get(
      "/account/applications/:application_key/:surface_id/federated",
      ApplicationHostController,
      :user_federated
    )

    get(
      "/admin/applications/:application_key/federated",
      ApplicationHostController,
      :admin_federated
    )

    get(
      "/admin/applications/:application_key/:surface_id/federated",
      ApplicationHostController,
      :admin_federated
    )

    get(
      "/missions/:mission_id/ops/telemetry/explore",
      LegacyOpsRedirectController,
      :telemetry_explore
    )

    get(
      "/missions/:mission_id/ops/dashboards/:dashboard_id/export",
      DashboardExportController,
      :show
    )

    live_session :application,
      on_mount: [{CadenceWeb.UserAuth, :require_user_scope}],
      layout: {CadenceWeb.Layouts, :host} do
      live("/", HostPageLive, :show, metadata: %{host_policy: :organization})
      live("/missions", HostPageLive, :index, metadata: %{host_policy: :organization})
      live("/missions/new", HostPageLive, :new, metadata: %{host_policy: :organization})

      live("/provider-accounts", HostPageLive, :index,
        metadata: %{host_policy: :provider_accounts}
      )

      live("/provider-accounts/new", HostPageLive, :new,
        metadata: %{host_policy: :provider_accounts}
      )

      live("/provider-accounts/:provider_account_id", HostPageLive, :show,
        metadata: %{host_policy: :provider_accounts}
      )

      live("/missions/:mission_id", HostPageLive, :show, metadata: %{host_policy: :mission})

      live("/missions/:mission_id/spacecraft", HostPageLive, :index,
        metadata: %{host_policy: :spacecraft}
      )

      live("/missions/:mission_id/spacecraft/new", HostPageLive, :new,
        metadata: %{host_policy: :spacecraft}
      )

      live("/missions/:mission_id/spacecraft/profiles", HostPageLive, :index,
        metadata: %{host_policy: :spacecraft}
      )

      live("/missions/:mission_id/spacecraft/profiles/new", HostPageLive, :new,
        metadata: %{host_policy: :spacecraft}
      )

      live("/missions/:mission_id/spacecraft/profiles/:profile_id", HostPageLive, :show,
        metadata: %{host_policy: :spacecraft}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id", HostPageLive, :show,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id/identity", HostPageLive, :identity,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id/edit", HostPageLive, :edit,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id/readiness", HostPageLive, :show,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id/routing", HostPageLive, :show,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id/commanding", HostPageLive, :show,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/missions/:mission_id/catalog", HostPageLive, :index,
        metadata: %{host_policy: :catalog}
      )

      live("/missions/:mission_id/catalog/new", HostPageLive, :new,
        metadata: %{host_policy: :catalog}
      )

      live("/missions/:mission_id/catalog/databases/:catalog_database_id", HostPageLive, :show,
        metadata: %{host_policy: :catalog}
      )

      live("/missions/:mission_id/catalog/revisions/:catalog_revision_id", HostPageLive, :show,
        metadata: %{host_policy: :catalog}
      )

      live("/missions/:mission_id/catalog/artifacts/:artifact_id", HostPageLive, :show,
        metadata: %{host_policy: :catalog}
      )

      live("/missions/:mission_id/catalog/imports/:import_run_id", HostPageLive, :show,
        metadata: %{host_policy: :catalog}
      )

      live("/missions/:mission_id/comms", HostPageLive, :index, metadata: %{host_policy: :comms})

      live("/missions/:mission_id/comms/transports", HostPageLive, :index,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/transports/new", HostPageLive, :new,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/transports/:transport_id", HostPageLive, :show,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/ground-stations", HostPageLive, :index,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/ground-stations/new", HostPageLive, :new,
        metadata: %{host_policy: :comms}
      )

      live(
        "/missions/:mission_id/comms/ground-stations/:ground_station_id/edit",
        HostPageLive,
        :edit,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/ground-stations/:ground_station_id", HostPageLive, :show,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/routing", HostPageLive, :index,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/routing/new", HostPageLive, :new,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/routing/:routing_rule_id", HostPageLive, :show,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/validation", HostPageLive, :index,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/providers", HostPageLive, :index,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/providers/new", HostPageLive, :new,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/comms/providers/:provider_id", HostPageLive, :show,
        metadata: %{host_policy: :comms}
      )

      live("/missions/:mission_id/ops", HostPageLive, :index, metadata: %{host_policy: :ops})

      live("/missions/:mission_id/ops/dashboards/new", HostPageLive, :new,
        metadata: %{host_policy: :ops_dashboard_author}
      )

      live("/missions/:mission_id/ops/dashboards/library", HostPageLive, :index,
        metadata: %{host_policy: :ops_dashboard_author}
      )

      live("/missions/:mission_id/ops/dashboards/playlists", HostPageLive, :index,
        metadata: %{host_policy: :ops_dashboard_author}
      )

      live("/missions/:mission_id/ops/dashboards/:dashboard_id/edit", HostPageLive, :edit,
        metadata: %{host_policy: :ops_dashboard_author}
      )

      live("/missions/:mission_id/ops/dashboards/:dashboard_id/settings", HostPageLive, :show,
        metadata: %{host_policy: :ops_dashboard_author}
      )

      live("/missions/:mission_id/ops/dashboards", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/dashboard-shares/:share_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/dashboard-snapshots/:snapshot_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live(
        "/missions/:mission_id/ops/dashboards/playlists/:playlist_id/present",
        HostPageLive,
        :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/data-sources", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/data-sources/:data_source_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/data-operations", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning/new", HostPageLive, :new,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning/policy", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/requirement-templates", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/requirements", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/requirements/new", HostPageLive, :new,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/requirements/:contact_requirement_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/plans/:contact_plan_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/contacts", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/contacts/records/:contact_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/contacts/:provider_reservation_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/alarms", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/timeline", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands/stages", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands/stages/new", HostPageLive, :new,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands/stages/:command_stage_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands/new", HostPageLive, :new,
        metadata: %{host_policy: :ops}
      )

      live(
        "/missions/:mission_id/ops/commands/requests/:command_request_id/history",
        HostPageLive,
        :show,
        metadata: %{host_policy: :ops}
      )

      live(
        "/missions/:mission_id/ops/commands/requests/:command_request_id/queue",
        HostPageLive,
        :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands/requests/:command_request_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/explore", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/dashboards/:dashboard_id/activity", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/dashboards/:dashboard_id", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/activations", HostPageLive, :index,
        metadata: %{host_policy: :ops_admin}
      )

      live("/missions/:mission_id/ops/data-sources/registration/new", HostPageLive, :new,
        metadata: %{host_policy: :ops_admin}
      )

      live(
        "/missions/:mission_id/ops/data-sources/:data_source_id/settings",
        HostPageLive,
        :settings,
        metadata: %{host_policy: :ops_admin}
      )

      live("/missions/:mission_id/ops/data-operations/manage", HostPageLive, :manage,
        metadata: %{host_policy: :ops_admin}
      )

      live("/missions/:mission_id/applications", HostPageLive, :index,
        metadata: %{host_policy: :mission}
      )

      live("/missions/:mission_id/spacecraft/:spacecraft_id/applications", HostPageLive, :index,
        metadata: %{host_policy: :spacecraft_show}
      )

      live("/notifications", HostPageLive, :index, metadata: %{host_policy: :user})
      live("/admin", HostPageLive, :index, metadata: %{host_policy: :admin})
      live("/admin/runtime", HostPageLive, :index, metadata: %{host_policy: :admin})
      live("/admin/organizations", HostPageLive, :index, metadata: %{host_policy: :admin})
      live("/admin/organizations/new", HostPageLive, :new, metadata: %{host_policy: :admin})
      live("/admin/organizations/:org_id", HostPageLive, :show, metadata: %{host_policy: :admin})

      live("/admin/organizations/:org_id/invite", HostPageLive, :invite,
        metadata: %{host_policy: :admin}
      )
    end

    live_session :mission,
      on_mount: [
        {CadenceWeb.OrganizationAuth, :require_organization_scope},
        {CadenceWeb.MissionAuth, :load_mission},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :mission_sidebar} do
      live(
        "/missions/:mission_id/applications/:application_key",
        ApplicationHostLive,
        :show
      )

      live(
        "/missions/:mission_id/applications/:application_key/:surface_id",
        ApplicationHostLive,
        :show
      )
    end

    live_session :spacecraft_show,
      on_mount: [
        {CadenceWeb.OrganizationAuth, :require_organization_scope},
        {CadenceWeb.MissionAuth, :load_mission},
        {CadenceWeb.SpacecraftAuth, :load_spacecraft},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :mission_sidebar} do
      live(
        "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key",
        ApplicationHostLive,
        :show
      )

      live(
        "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id",
        ApplicationHostLive,
        :show
      )
    end

    # Legacy application URLs redirect to the generic application host. Keep
    # compatibility mappings out of ApplicationHostLive so new applications do
    # not require host actions or routes.
    get(
      "/missions/:mission_id/spacecraft/:spacecraft_id/telemetry",
      LegacyApplicationRedirectController,
      :telemetry_decom
    )

    get(
      "/missions/:mission_id/spacecraft/:spacecraft_id/telemetry_decom",
      LegacyApplicationRedirectController,
      :telemetry_decom
    )

    # Legacy comms URL aliases -- 301 redirect to canonical paths so old
    # bookmarks (and any unmigrated outbound links) still resolve.
    get(
      "/missions/:mission_id/comms/links",
      LegacyCommsRedirectController,
      :link_templates_index
    )

    get(
      "/missions/:mission_id/comms/links/new",
      LegacyCommsRedirectController,
      :shared_link_new
    )

    get(
      "/missions/:mission_id/comms/path-templates",
      LegacyCommsRedirectController,
      :link_templates_index
    )

    get(
      "/missions/:mission_id/comms/path-templates/new",
      LegacyCommsRedirectController,
      :link_templates_new
    )

    get(
      "/missions/:mission_id/comms/path-templates/:path_template_id",
      LegacyCommsRedirectController,
      :link_templates_show
    )

    get(
      "/missions/:mission_id/comms/path-templates/:path_template_id/new-version",
      LegacyCommsRedirectController,
      :link_templates_new_version
    )

    get(
      "/missions/:mission_id/comms/transport-profiles",
      LegacyCommsRedirectController,
      :protocol_behaviors_index
    )

    get(
      "/missions/:mission_id/comms/transport-profiles/new",
      LegacyCommsRedirectController,
      :protocol_behaviors_new
    )

    get(
      "/missions/:mission_id/comms/transport-profiles/:transport_profile_id",
      LegacyCommsRedirectController,
      :protocol_behaviors_show
    )

    get(
      "/missions/:mission_id/comms/transport-profiles/:transport_profile_id/new-version",
      LegacyCommsRedirectController,
      :protocol_behaviors_new_version
    )

    get(
      "/missions/:mission_id/comms/provider-profiles",
      LegacyCommsRedirectController,
      :providers_index
    )

    get(
      "/missions/:mission_id/comms/provider-profiles/new",
      LegacyCommsRedirectController,
      :providers_new
    )

    get(
      "/missions/:mission_id/comms/provider-profiles/:provider_profile_id",
      LegacyCommsRedirectController,
      :providers_show
    )

    get(
      "/missions/:mission_id/comms/provider-profiles/:provider_profile_id/new-version",
      LegacyCommsRedirectController,
      :providers_new_version
    )

    get(
      "/missions/:mission_id/comms/source-endpoints",
      LegacyCommsRedirectController,
      :runtime_identities_index
    )

    get(
      "/missions/:mission_id/comms/source-endpoints/new",
      LegacyCommsRedirectController,
      :runtime_identities_new
    )

    get(
      "/missions/:mission_id/comms/advanced/runtime-identities",
      LegacyCommsRedirectController,
      :runtime_identities_index
    )

    get(
      "/missions/:mission_id/comms/advanced/runtime-identities/new",
      LegacyCommsRedirectController,
      :runtime_identities_new
    )
  end

  scope "/api", CadenceWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  scope "/api/cadence/frontend-release/v1", CadenceWeb do
    pipe_through([:api, :frontend_release_publisher])

    put("/objects/:digest", FrontendReleasePublisherController, :upload)
    post("/releases", FrontendReleasePublisherController, :create)
    post("/promotions", FrontendReleasePublisherController, :promote)
  end

  scope "/api/cadence/application-host/v1", CadenceWeb do
    pipe_through([:browser, :require_authenticated_user, :application_host_json])

    get("/missions/:mission_id/catalog", ApplicationHostController, :catalog)

    get(
      "/missions/:mission_id/spacecraft/:spacecraft_id/catalog",
      ApplicationHostController,
      :catalog
    )

    get("/catalog", ApplicationHostController, :catalog)

    post("/missions/:mission_id/query", ApplicationHostController, :query)

    post(
      "/missions/:mission_id/spacecraft/:spacecraft_id/query",
      ApplicationHostController,
      :query
    )

    post("/missions/:mission_id/actions", ApplicationHostController, :actions)

    post(
      "/missions/:mission_id/spacecraft/:spacecraft_id/actions",
      ApplicationHostController,
      :actions
    )

    post("/query", ApplicationHostController, :query)
    post("/actions", ApplicationHostController, :actions)
  end

  scope "/api", CadenceWeb do
    pipe_through([:api, :authenticated_api])

    get("/current_scope", CurrentScopeController, :show)

    scope "/organizations/:organization_id" do
      get("/", OrganizationController, :show)

      get("/missions", MissionController, :index)
      post("/missions", MissionController, :create)
      get("/missions/:mission_id", MissionController, :show)

      get("/service_identities", ServiceIdentityController, :index)
      post("/service_identities", ServiceIdentityController, :create)

      scope "/missions/:mission_id" do
        get("/mission_health", MissionHealthController, :show)
        get("/mission_events", MissionEventController, :index)
        get("/telemetry/latest", TelemetryController, :latest_values)
        get("/telemetry/points/:point_id/latest", TelemetryController, :latest_value)
        get("/telemetry/points/:point_id/history", TelemetryController, :history)
        post("/dev/space_packets", DevSpacePacketController, :create)
        post("/dev/tm_frames", DevTMFrameController, :create)
        get("/catalog/importers", CatalogImporterController, :index)
        get("/catalog_artifacts", CatalogArtifactController, :index)
        post("/catalog_artifacts", CatalogArtifactController, :create)
        get("/catalog_artifacts/:artifact_id", CatalogArtifactController, :show)
        get("/catalog_import_runs", CatalogImportRunController, :index)
        post("/catalog_import_runs", CatalogImportRunController, :create)
        get("/catalog_import_runs/:import_run_id", CatalogImportRunController, :show)
        get("/spacecraft", SpacecraftController, :index)
        post("/spacecraft", SpacecraftController, :create)
        get("/spacecraft/:spacecraft_id", SpacecraftController, :show)
        get("/provider_profiles", ProviderProfileController, :index)
        post("/provider_profiles", ProviderProfileController, :create)

        get(
          "/provider_profiles/:provider_profile_id/versions",
          ProviderProfileController,
          :versions
        )

        get(
          "/provider_profiles/:provider_profile_id/versions/:version",
          ProviderProfileController,
          :show_version
        )

        get("/provider_profiles/:provider_profile_id", ProviderProfileController, :show)
        patch("/provider_profiles/:provider_profile_id", ProviderProfileController, :update)
        delete("/provider_profiles/:provider_profile_id", ProviderProfileController, :delete)
        get("/transport_profiles", TransportProfileController, :index)
        post("/transport_profiles", TransportProfileController, :create)

        get(
          "/transport_profiles/:transport_profile_id/versions",
          TransportProfileController,
          :versions
        )

        get(
          "/transport_profiles/:transport_profile_id/versions/:version",
          TransportProfileController,
          :show_version
        )

        get("/transport_profiles/:transport_profile_id", TransportProfileController, :show)
        patch("/transport_profiles/:transport_profile_id", TransportProfileController, :update)
        delete("/transport_profiles/:transport_profile_id", TransportProfileController, :delete)
        get("/path_templates", PathTemplateController, :index)
        post("/path_templates", PathTemplateController, :create)

        post(
          "/path_templates/:path_template_id/link_assignments",
          LinkAssignmentController,
          :apply_template
        )

        get("/path_templates/:path_template_id/versions", PathTemplateController, :versions)

        get(
          "/path_templates/:path_template_id/versions/:version",
          PathTemplateController,
          :show_version
        )

        get("/path_templates/:path_template_id", PathTemplateController, :show)
        patch("/path_templates/:path_template_id", PathTemplateController, :update)
        delete("/path_templates/:path_template_id", PathTemplateController, :delete)
        get("/link_assignments", LinkAssignmentController, :index)
        post("/link_assignments", LinkAssignmentController, :create)
        get("/link_assignments/:link_assignment_id", LinkAssignmentController, :show)
        delete("/link_assignments/:link_assignment_id", LinkAssignmentController, :delete)
        get("/spacecraft/:spacecraft_id/source_endpoints", SourceEndpointController, :index)
        post("/spacecraft/:spacecraft_id/source_endpoints", SourceEndpointController, :create)

        get("/source_endpoints", SourceEndpointController, :index)
        post("/source_endpoints", SourceEndpointController, :create)
        get("/source_endpoints/:source_endpoint_id", SourceEndpointController, :show)

        get("/command_stages", CommandStageController, :index)
        post("/command_stages", CommandStageController, :create)
        get("/command_stages/:command_stage_id", CommandStageController, :show)
        patch("/command_stages/:command_stage_id", CommandStageController, :update)
        post("/command_stages/:command_stage_id/submit", CommandStageController, :submit)

        get("/command_stages/:command_stage_id/items", StagedCommandItemController, :index)
        post("/command_stages/:command_stage_id/items", StagedCommandItemController, :create)

        get("/staged_command_items/:staged_command_item_id", StagedCommandItemController, :show)

        patch(
          "/staged_command_items/:staged_command_item_id",
          StagedCommandItemController,
          :update
        )

        get("/command_requests", CommandRequestController, :index)
        post("/command_requests", CommandRequestController, :create)
        get("/command_requests/:command_request_id", CommandRequestController, :show)
        post("/command_requests/:command_request_id/approve", CommandRequestController, :approve)
        post("/command_requests/:command_request_id/reject", CommandRequestController, :reject)
        post("/command_requests/:command_request_id/enqueue", CommandRequestController, :enqueue)

        get("/command_approvals", CommandApprovalController, :index)
        get("/command_approvals/:command_approval_id", CommandApprovalController, :show)

        get("/command_queue_entries", CommandQueueEntryController, :index)
        get("/command_queue_entries/:command_queue_entry_id", CommandQueueEntryController, :show)

        post(
          "/command_queue_entries/:command_queue_entry_id/release",
          CommandQueueEntryController,
          :release
        )

        get("/command_release_attempts", CommandReleaseAttemptController, :index)

        get(
          "/command_release_attempts/:command_release_attempt_id",
          CommandReleaseAttemptController,
          :show
        )

        get("/command_verifier_instances", CommandVerifierInstanceController, :index)

        get(
          "/command_verifier_instances/:command_verifier_instance_id",
          CommandVerifierInstanceController,
          :show
        )

        get("/scheduled_contacts", ScheduledContactController, :index)
        post("/scheduled_contacts", ScheduledContactController, :create)
        get("/scheduled_contacts/:scheduled_contact_id", ScheduledContactController, :show)

        post(
          "/scheduled_contacts/:scheduled_contact_id/realize",
          ScheduledContactController,
          :realize
        )

        post(
          "/scheduled_contacts/:scheduled_contact_id/cancel",
          ScheduledContactController,
          :cancel
        )

        get("/realized_contacts", RealizedContactController, :index)

        get(
          "/realized_contacts/:realized_contact_id/runtime",
          RealizedContactController,
          :runtime
        )

        get(
          "/realized_contacts/:realized_contact_id/paths/:path_id/runtime",
          RealizedContactController,
          :path_runtime
        )

        get("/realized_contacts/:realized_contact_id", RealizedContactController, :show)

        post(
          "/realized_contacts/:realized_contact_id/end_early",
          RealizedContactController,
          :end_early
        )

        get("/contact_actions", ContactActionController, :index)

        get("/packet_definitions", PacketDefinitionController, :index)
        post("/packet_definitions", PacketDefinitionController, :create)

        post("/binding_sets", BindingSetController, :create)
        get("/binding_sets/:binding_set_id/versions/:version", BindingSetController, :show)

        post("/activations", ActivationController, :create)
        get("/activations/active", ActivationController, :show)
        get("/activation_requests", ActivationController, :index)
        get("/activation_requests/:activation_request_id", ActivationController, :show_request)

        post(
          "/activation_requests/:activation_request_id/approve",
          ActivationController,
          :approve
        )

        post(
          "/activation_requests/:activation_request_id/reject",
          ActivationController,
          :reject
        )
      end
    end
  end
end
