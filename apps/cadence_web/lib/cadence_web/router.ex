defmodule CadenceWeb.Router do
  use CadenceWeb, :router

  require CadenceWeb.Console.DevIngestRoutes, as: DevIngestRoutes

  @dev_ingest_routes Application.compile_env(:cadence_web, :dev_ingest_routes, false)

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

  # Apogee console SPA JSON API: same-origin browser session cookie, CSRF
  # token in the x-csrf-token header on writes, JSON problems on failure.
  pipeline :console_api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
    plug(CadenceWeb.Console.Plugs.APISession)
  end

  # L5: sign-in and invitation links, which work signed out (CSRF still enforced).
  pipeline :console_auth_api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
    plug(CadenceWeb.Console.Plugs.AuthAPISession)
  end

  pipeline :console_mission do
    plug(CadenceWeb.Console.Plugs.MissionScope)
  end

  pipeline :console_organization do
    plug(CadenceWeb.Console.Plugs.OrganizationScope)
  end

  # Kubelet probes do not carry browser sessions or API credentials.
  # Only coarse process/database readiness is exposed here.
  scope "/health", CadenceWeb do
    pipe_through(:api)
    get("/live", HealthController, :live)
    get("/ready", HealthController, :ready)
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

  # Console SPA document. Every client-side route returns the same shell; unauthenticated GETs
  # redirect to /console/sign-in and come back here. The auth screens are served without a
  # session (the SPA routes them); the site root opens the console.
  scope "/console", CadenceWeb.Console do
    pipe_through(:browser)

    get("/sign-in", SPAController, :index)
    get("/invitations/:token", SPAController, :index)
    get("/no-organization", SPAController, :index)
  end

  scope "/", CadenceWeb.Console do
    pipe_through(:browser)

    get("/", SPAController, :root)
  end

  scope "/console", CadenceWeb.Console do
    pipe_through([:browser, :require_authenticated_scope])

    get("/", SPAController, :index)
    get("/*path", SPAController, :index)
  end

  scope "/", CadenceWeb do
    pipe_through([:browser, :require_authenticated_scope])

    live_session :application,
      on_mount: [{CadenceWeb.UserAuth, :require_user_scope}],
      layout: {CadenceWeb.Layouts, :host} do
      live("/missions/:mission_id/ops", HostPageLive, :index, metadata: %{host_policy: :ops})

      live("/missions/:mission_id/ops/data-operations", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning/new", HostPageLive, :new,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id", HostPageLive, :show,
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

      live(
        "/missions/:mission_id/ops/commands/requests/:command_request_id/history",
        HostPageLive,
        :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/commands", HostPageLive, :index,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/explore", HostPageLive, :show,
        metadata: %{host_policy: :ops}
      )

      live("/missions/:mission_id/ops/data-operations/manage", HostPageLive, :manage,
        metadata: %{host_policy: :ops_admin}
      )
    end
  end

  # L5 auth JSON (owner: api-ops). Contract: docs/apogee/api/session.md
  scope "/api/v1/auth", CadenceWeb.Console do
    pipe_through(:console_auth_api)

    post("/sign-in", SignInController, :create)
    get("/invitations/:token", InvitationLinkController, :show)
    post("/invitations/:token/accept", InvitationLinkController, :accept)
    post("/invitations/:token/decline", InvitationLinkController, :decline)
  end

  scope "/api/v1", CadenceWeb.Console do
    pipe_through(:console_api)

    get("/session", SessionController, :show)
    delete("/session", SessionController, :delete)
    put("/session/organization", SessionController, :update_organization)
    # L6 admin mode step-up (owner: api-ops). Contract: docs/apogee/api/session.md
    post("/session/admin-mode", SessionController, :enter_admin_mode)
    delete("/session/admin-mode", SessionController, :leave_admin_mode)

    # L7 platform admin area (owner: api-ops). Contract: docs/apogee/api/admin.md
    scope "/admin" do
      get("/organizations", AdminController, :organizations)
      get("/organizations/slug", AdminController, :slug)
      post("/organizations", AdminController, :create_organization)
      get("/organizations/:id", AdminController, :organization)
      post("/organizations/:id/invitations", AdminController, :invite)
      delete("/organizations/:id/invitations/:invitation_id", AdminController, :withdraw)
      get("/service-identities", AdminController, :service_identities)
      post("/service-identities", AdminController, :issue)
      post("/service-identities/:id/rotate", AdminController, :rotate)
      delete("/service-identities/:id", AdminController, :revoke)
      get("/runtime", AdminController, :runtime)
      get("/audit", AdminController, :audit)
    end

    # -- Account (owner: api): the signed-in user's own password and sessions.
    put("/account/password", AccountController, :change_password)
    get("/account/sessions", AccountController, :sessions)
    delete("/account/sessions", AccountController, :revoke_others)
    delete("/account/sessions/:session_id", AccountController, :revoke_session)
    # L21: my pending invitations (the token path stays server-rendered, /invitations/:token).
    get("/account/invitations", AccountInvitationController, :index)
    post("/account/invitations/:invitation_id/accept", AccountInvitationController, :accept)
    post("/account/invitations/:invitation_id/decline", AccountInvitationController, :decline)
    # #709: my notices (the legacy bell's), and Mark read.
    get("/account/notices", AccountNoticeController, :index)
    post("/account/notices/:notice_id/read", AccountNoticeController, :read)

    scope "/missions/:mission_id" do
      pipe_through(:console_mission)

      get("/", MissionController, :show)

      # -- Ops (owner: api-ops). Contracts: docs/apogee/api/ops.md
      get("/fleet", FleetController, :show)
      get("/alarms", AlarmController, :index)
      get("/telemetry/points", TelemetryPointController, :index)
      # Compose B2 "Now" (owner: api): latest values for a few points across many spacecraft.
      post("/telemetry/latest", TelemetryLatestController, :latest)
      get("/telemetry/points/:point_id/history", PointController, :history)
      # §11c(D) D1 (owner: api): one sample for Investigate's Sample aside.
      get("/telemetry/samples/:sample_id", TelemetrySampleController, :show)
      get("/limits/points/:point_id/intervals", PointController, :limit_intervals)
      get("/action-queue", ActionQueueController, :show)
      get("/counts", OpsCountsController, :show)
      # #780: development ingest, mounted in dev and test only (compiled out of prod).
      DevIngestRoutes.mount(@dev_ingest_routes)
      # Dashboards (owner: api-ops). Contract: docs/apogee/api/dashboards.md
      get("/dashboards", DashboardDirectoryController, :index)
      post("/dashboards", DashboardDirectoryController, :create)
      get("/dashboards/:dashboard_id", DashboardController, :show)
      put("/dashboards/:dashboard_id/star", DashboardDirectoryController, :star)
      delete("/dashboards/:dashboard_id/star", DashboardDirectoryController, :unstar)
      post("/dashboards/:dashboard_id/views", DashboardDirectoryController, :view)
      post("/dashboards/:dashboard_id/archive", DashboardDirectoryController, :archive)
      post("/dashboards/:dashboard_id/restore", DashboardDirectoryController, :restore)
      post("/dashboards/:dashboard_id/duplicate", DashboardDirectoryController, :duplicate)
      # Dashboard editing D7-D13 (owner: api): stateless, the browser keeps the commands.
      post("/dashboards/:dashboard_id/preview", DashboardAuthoringController, :preview)
      post("/dashboards/:dashboard_id/observables", DashboardAuthoringController, :observables)
      post("/dashboards/:dashboard_id/save", DashboardAuthoringController, :save)
      post("/dashboards/:dashboard_id/rebase", DashboardAuthoringController, :rebase)
      post("/dashboards/:dashboard_id/copy", DashboardAuthoringController, :copy)
      get("/dashboards/:dashboard_id/versions", DashboardAuthoringController, :versions)
      get("/dashboards/:dashboard_id/versions/compare", DashboardAuthoringController, :compare)

      post(
        "/dashboards/:dashboard_id/versions/:version/restore",
        DashboardAuthoringController,
        :restore
      )

      # Dashboard settings D14-D19 (owner: api).
      get("/dashboards/:dashboard_id/activity", DashboardSettingsController, :activity)
      get("/dashboards/:dashboard_id/diagnostics", DashboardSettingsController, :diagnostics)
      get("/dashboards/:dashboard_id/export", DashboardSettingsController, :export)
      # D20 shared views (owner: api): the link of a share or a snapshot.
      get("/dashboard-shares/:share_id", DashboardSharedViewController, :share)
      get("/dashboard-snapshots/:snapshot_id", DashboardSharedViewController, :snapshot)
      # D23/D24 playlists (owner: api).
      get("/dashboard-playlists", DashboardPlaylistController, :index)
      post("/dashboard-playlists", DashboardPlaylistController, :create)
      get("/dashboard-playlists/:playlist_id", DashboardPlaylistController, :show)
      patch("/dashboard-playlists/:playlist_id", DashboardPlaylistController, :update)
      delete("/dashboard-playlists/:playlist_id", DashboardPlaylistController, :delete)
      # D21/D22 library (owner: api).
      get("/dashboard-library", DashboardLibraryController, :index)
      post("/dashboard-library", DashboardLibraryController, :create)
      get("/dashboard-library/:item_id", DashboardLibraryController, :show)
      patch("/dashboard-library/:item_id", DashboardLibraryController, :update)
      delete("/dashboard-library/:item_id", DashboardLibraryController, :delete)
      post("/dashboard-library/:item_id/versions", DashboardLibraryController, :add_version)
      get("/dashboards/:dashboard_id/settings", DashboardSharingController, :show)
      patch("/dashboards/:dashboard_id/settings", DashboardSharingController, :update)
      post("/dashboards/:dashboard_id/shares", DashboardSharingController, :create_share)

      delete(
        "/dashboards/:dashboard_id/shares/:share_id",
        DashboardSharingController,
        :revoke_share
      )

      post("/dashboards/:dashboard_id/snapshots", DashboardSharingController, :create_snapshot)

      delete(
        "/dashboards/:dashboard_id/snapshots/:snapshot_id",
        DashboardSharingController,
        :delete_snapshot
      )

      get("/passes", PassController, :index)
      get("/contact-findings", ContactFindingsController, :index)
      get("/passes/:id", PassController, :show)
      get("/passes/:id/reservation", PassReservationController, :show)
      get("/contacts/:contact_id/record", ContactRecordController, :show)
      post("/passes/:id/recover-uplink", PassController, :recover_uplink)
      post("/passes/:id/release", PassController, :release)
      # U55 cancel or end a pass's contact (owner: api). Contract: docs/apogee/api/contacts.md
      post("/passes/:id/cancel-contact", PassContactController, :cancel)
      # U65: the model approval gate (owner: api). Contract: docs/apogee/api/setup.md
      get("/mission-model-revisions", MissionModelRevisionController, :index)
      get("/mission-model-revisions/:id", MissionModelRevisionController, :show)
      post("/mission-model-revisions/:id/comparison", MissionModelRevisionController, :compare)
      post("/mission-model-revisions/:id/approve", MissionModelRevisionController, :approve)
      post("/mission-model-revisions/:id/reject", MissionModelRevisionController, :reject)
      post("/mission-model-revisions/:id/withdraw", MissionModelRevisionController, :withdraw)
      post("/passes/:id/end-contact", PassContactController, :finish)
      # U46 named release (owner: api). Contract: docs/apogee/api/commanding.md
      post(
        "/contacts/:realized_contact_id/release",
        ContactReleaseController,
        :release
      )

      # L15 single bookings (owner: api).
      get("/single-bookings/routes", SingleBookingController, :routes)
      post("/single-bookings/search", SingleBookingController, :search)
      post("/single-bookings", SingleBookingController, :create)

      get("/realized-contacts/:realized_contact_id/runtime", ContactRuntimeController, :runtime)

      get(
        "/realized-contacts/:realized_contact_id/paths/:path_id/runtime",
        ContactRuntimeController,
        :path_runtime
      )

      get("/commands", CommandCatalogController, :index)
      get("/commands/:command_id", CommandCatalogController, :show)
      get("/command-policies", CommandGroupController, :policies)
      get("/command-endpoints", CommandGroupController, :endpoints)
      # Compose draft (owner: api). Contract: docs/apogee/api/commanding.md §Compose draft
      get("/command-draft", CommandDraftController, :show)
      put("/command-draft", CommandDraftController, :update)
      delete("/command-draft", CommandDraftController, :delete)
      get("/station-availability", StationAvailabilityController, :index)
      get("/pass-review", PassReviewController, :summary)
      get("/pass-review/rows", PassReviewController, :rows)
      get("/pass-review/daily", PassReviewController, :daily)
      get("/station-availability/:station_id", StationAvailabilityController, :show)
      get("/station-availability/:station_id/impact", StationAvailabilityController, :impact)

      post(
        "/station-availability/:station_id/windows",
        StationAvailabilityController,
        :create_window
      )

      post(
        "/station-availability/windows/:window_id/clear",
        StationAvailabilityController,
        :clear_window
      )

      post("/command-groups/preflight", CommandGroupController, :preflight)
      get("/command-groups", CommandGroupController, :index)
      post("/command-groups", CommandGroupController, :create)
      get("/command-groups/:command_group_id", CommandGroupController, :show)

      get(
        "/command-groups/:command_group_id/preflight",
        CommandGroupController,
        :review_preflight
      )

      get(
        "/command-groups/:command_group_id/verifier-series",
        CommandGroupController,
        :verifier_series
      )

      post("/command-groups/:command_group_id/decision", CommandGroupController, :decision)
      post("/command-groups/:command_group_id/abort", CommandGroupController, :abort)
      post("/command-groups/:command_group_id/notes", CommandGroupController, :add_note)

      post(
        "/command-requests/:command_request_id/cancel",
        CommandGroupController,
        :cancel_request
      )

      get(
        "/command-requests/:command_request_id/encoding",
        CommandEncodingController,
        :show
      )

      get("/command-requests/:command_request_id/brief", CommandEncodingController, :brief)

      get(
        "/command-requests/:command_request_id/history",
        CommandRequestHistoryController,
        :show
      )

      get("/alarm-episodes", AlarmEpisodeController, :index)
      get("/alarm-episodes/:episode_id", AlarmEpisodeController, :show)
      post("/alarm-episodes/:episode_id/acknowledge", AlarmEpisodeController, :acknowledge)
      post("/alarm-episodes/:episode_id/assign", AlarmEpisodeController, :assign)
      post("/alarm-episodes/:episode_id/hand-off", AlarmEpisodeController, :hand_off)
      post("/alarm-episodes/:episode_id/notes", AlarmEpisodeController, :add_note)
      # Investigate History (owner: api). Contract: docs/apogee/api/alarms-console.md §History
      get("/alarm-episodes/:episode_id/history", AlarmHistoryController, :episode)
      get("/spacecraft/:spacecraft_id/alarm-episodes", AlarmHistoryController, :spacecraft)
      get("/spacecraft/:spacecraft_id/passes", SpacecraftPassesController, :show)
      # L14 provider-change decisions (owner: api), ahead of the generic attention verbs.
      post("/attention/provider_change/:id/approve", ProviderChangeController, :approve)
      post("/attention/provider_change/:id/reject", ProviderChangeController, :reject)
      post("/attention/provider_change/:id/acknowledge", ProviderChangeController, :acknowledge)
      # U37 (#847): one pass's open settlement item, without reading the action queue.
      get("/attention/contact_settlement", AttentionController, :settlement)
      post("/attention/:source/:id/acknowledge", AttentionController, :acknowledge)
      post("/attention/:source/:id/resolve", AttentionController, :resolve)
      post("/attention/:source/:id/retry", AttentionController, :retry)

      # -- Setup (owner: api). Contracts: docs/apogee/api/setup.md
      get("/spacecraft", SpacecraftController, :index)
      # #847: before :spacecraft_id, so "names" isn't read as an id.
      get("/spacecraft/names", SpacecraftController, :names)
      get("/spacecraft/:spacecraft_id", SpacecraftDetailController, :show)

      # #889 (slice 1 of #732): orbits as SGP4 element sets. Contract: docs/apogee/api/element-sets.md
      post("/element-sets", ElementSetController, :bulk)
      get("/spacecraft/:spacecraft_id/element-sets", ElementSetController, :index)
      post("/spacecraft/:spacecraft_id/element-sets", ElementSetController, :create)
      get("/spacecraft/:spacecraft_id/element-sets/current", ElementSetController, :current)
      # #891 (slice 3 of #732): predicted passes. Contract: docs/apogee/api/predicted-passes.md
      get("/predicted-passes", PredictedPassController, :index)
      post("/predicted-passes/recompute", PredictedPassController, :recompute)
      get("/spacecraft/:spacecraft_id/predicted-passes", PredictedPassController, :spacecraft)
      get("/spacecraft/:spacecraft_id/source-endpoints", SourceEndpointController, :index)
      post("/spacecraft/:spacecraft_id/source-endpoints", SourceEndpointController, :create)
      get("/source-endpoints", SourceEndpointController, :index)
      post("/source-endpoints", SourceEndpointController, :create)
      get("/source-endpoints/:source_endpoint_id", SourceEndpointController, :show)
      get("/spacecraft/:spacecraft_id/routes/:route_id", SpacecraftDetailController, :route)
      # TEMPORARY (removed with 9ac6dc8ee): the legacy route conversion (ux U79).
      get("/routes/legacy-conversion", LegacyConversionController, :show)
      post("/routes/legacy-conversion", LegacyConversionController, :stage)
      get("/spacecraft/:spacecraft_id/uplink", SpacecraftUplinkController, :show)
      get("/spacecraft/:spacecraft_id/configuration", SpacecraftConfigController, :show)

      # (B) a spacecraft's configuration workspace (owner: api). Contract: docs/apogee/api/setup.md
      get(
        "/spacecraft/:spacecraft_id/configuration/workspace",
        SpacecraftWorkspaceController,
        :show
      )

      put(
        "/spacecraft/:spacecraft_id/configuration/workspace/draft",
        SpacecraftWorkspaceController,
        :save_draft
      )

      post(
        "/spacecraft/:spacecraft_id/configuration/workspace/submit",
        SpacecraftWorkspaceController,
        :submit
      )

      get(
        "/spacecraft/:spacecraft_id/configuration/workspace/catalogs/:catalog_revision_id/packets",
        SpacecraftWorkspaceController,
        :packets
      )

      # One review of any number of spacecraft (#734). Contract: docs/apogee/api/setup.md
      post("/configuration/reviews", SpacecraftWorkspaceController, :reviews)

      # L19 spacecraft-scope apps (owner: api).
      get("/spacecraft/:spacecraft_id/apps", SpacecraftAppController, :index)
      post("/spacecraft/:spacecraft_id/apps/:key/install", SpacecraftAppController, :install)
      post("/spacecraft/:spacecraft_id/apps/:key/disable", SpacecraftAppController, :disable)
      post("/spacecraft/:spacecraft_id/apps/:key/uninstall", SpacecraftAppController, :uninstall)
      get("/profiles", ProfileController, :index)
      get("/profiles/:profile_id", ProfileDetailController, :show)
      get("/readiness", ReadinessController, :show)
      get("/catalog", CatalogController, :index)
      get("/catalog/imports/:import_run_id", CatalogController, :import_run)
      get("/catalog/revisions/:revision_id/rollout", CatalogController, :rollout)
      get("/catalog/revisions/:revision_id/apids", CatalogController, :apids)
      # L18 source files (owner: api).
      get("/catalog/artifacts/:artifact_id", CatalogController, :artifact)
      post("/catalog/artifacts/:artifact_id/reimport", CatalogController, :reimport)
      get("/catalog/artifacts/:artifact_id/download", CatalogController, :download)
      # L10 activation approvals (owner: api). Contract: docs/apogee/api/activations.md
      get("/activations", ActivationRequestController, :index)
      get("/activations/:request_id", ActivationRequestController, :show)

      get(
        "/activations/:request_id/configuration-changes",
        ActivationRequestController,
        :configuration_change_names
      )

      post("/activations/:request_id/approve", ActivationRequestController, :approve)
      post("/activations/:request_id/reject", ActivationRequestController, :reject)
      post("/activations/:request_id/resume", ActivationRequestController, :resume)
      post("/activations/:request_id/withdraw", ActivationRequestController, :withdraw)
      post("/catalog/imports", CatalogImportController, :create)
      get("/catalog/importers", CatalogImportController, :importers)
      get("/ground-stations", CommsController, :stations)
      get("/providers", CommsController, :providers)
      # L12 mission-provider writes (owner: api-ops).
      get("/providers/options", MissionProviderController, :options)
      post("/providers", MissionProviderController, :create)
      post("/providers/:provider_id/validate", MissionProviderController, :validate)
      post("/providers/:provider_id/sync", MissionProviderController, :sync)
      post("/providers/:provider_id/archive", MissionProviderController, :archive)

      get(
        "/providers/:provider_id/ephemeris/spacecraft",
        ProviderEphemerisController,
        :spacecraft
      )

      get("/transports", CommsController, :transports)
      get("/transports/:transport_id", CommsController, :transport)
      get("/routing-rules", CommsController, :routing_rules)
      get("/routing-rules/groups", CommsController, :routing_rule_groups)
      get("/data-sources", DataSourceController, :index)
      # L11 data-source writes (owner: api-ops). Contract: docs/apogee/api/setup.md
      get("/data-sources/options", DataSourceWritesController, :options)
      post("/data-sources", DataSourceWritesController, :create)
      get("/data-sources/:data_source_id", DataSourceWritesController, :show)
      post("/data-sources/:data_source_id/disable", DataSourceWritesController, :disable)
      post("/data-sources/:data_source_id/enable", DataSourceWritesController, :enable)
      post("/data-sources/:data_source_id/probe", DataSourceWritesController, :probe)
      post("/data-sources/:data_source_id/credential", DataSourceWritesController, :credential)
      post("/data-sources/:data_source_id/tsdb/:operation", DataSourceWritesController, :tsdb)
      # #90 / ux U53 (owner: api-ops): the mission's bindings, a platform binding's blast radius
      # and history.
      get("/data-source-bindings", DataSourceBindingsController, :index)

      get(
        "/data-source-bindings/:binding_id/blast-radius",
        DataSourceBindingsController,
        :blast_radius
      )

      get("/data-source-bindings/:binding_id/events", DataSourceBindingsController, :events)
      put("/data-source-bindings/:binding_id", DataSourceWritesController, :change_binding)
      post("/data-source-runs/:job_id/:action", DataSourceWritesController, :run_action)
      get("/settings", SettingsController, :show)
      put("/settings/:section_key", SettingsController, :update)
      get("/apps", AppController, :index)
      post("/apps/:key/install", AppController, :install)
      post("/apps/:key/disable", AppController, :disable)
      post("/apps/:key/uninstall", AppController, :uninstall)
      # L9 surface host: one surface's application-host catalog, status and surfaces.
      get("/apps/:key/surfaces/:surface_id/host", AppSurfaceController, :host)

      # -- Events and scheduling (owner: api, DECISIONS #26). Contracts: ops.md, scheduling.md
      get("/events", EventController, :index)
      get("/events/density", EventController, :density)
      get("/events/raw-kinds", EventController, :raw_kind_list)
      get("/events/:event_id", EventController, :show)
      post("/contact-plans/drafts", ContactDraftController, :create)
      get("/contact-plans/drafts/:run_id", ContactDraftController, :show)
      post("/contact-plans/drafts/:run_id/continue", ContactDraftController, :continue)
      get("/contact-plans/repairs/:run_id", ContactDraftController, :show_repair)
      post("/contact-plans/:plan_id/repairs", ContactDraftController, :repair)
      get("/contact-plans", ContactPlanController, :index)
      get("/contact-plans/setup", ContactPlanController, :setup)
      get("/contact-plans/demand", ContactPlanController, :demand)
      get("/contact-plans/days", ContactPlanDaysController, :index)
      get("/contact-plans/:plan_id", ContactPlanController, :show)
      get("/contact-plans/:plan_id/history", ContactPlanHistoryController, :show)
      post("/contact-plans/:plan_id/versions", ContactPlanController, :edit)
      get("/contact-plans/:plan_id/alternatives", ContactPlanController, :alternatives)
      post("/contact-plans/:plan_id/submit", ContactPlanController, :submit)
      post("/contact-plans/:plan_id/approve", ContactPlanReviewController, :approve)
      post("/contact-plans/:plan_id/reject", ContactPlanReviewController, :reject)
      get("/contact-planning/policy", ContactPlanningController, :policy)
      post("/contact-planning/policy", ContactPlanningController, :save_policy)

      post(
        "/contact-planning/policy/:version/decision",
        ContactPlanningController,
        :decide_policy
      )

      get("/contact-planning", ContactTemplateController, :summary)
      get("/contact-planning/templates", ContactTemplateController, :index)
      post("/contact-planning/templates", ContactTemplateController, :create)
      post("/contact-planning/templates/preview", ContactTemplateController, :preview)
      get("/contact-planning/templates/schema", ContactTemplateController, :schema)

      get(
        "/contact-planning/templates/:template_id/supersedes",
        ContactTemplateController,
        :supersedes
      )

      get(
        "/contact-planning/requirements/:requirement_id/supersedes",
        ContactTemplateController,
        :requirement_supersedes
      )

      get("/contact-planning/requirements", ContactRequirementController, :index)
      post("/contact-planning/requirements", ContactRequirementController, :create)
      get("/contact-planning/requirements/schema", ContactRequirementController, :schema)

      get(
        "/contact-planning/requirements/by-template",
        ContactRequirementController,
        :by_template
      )

      get("/contact-planning/requirements/:requirement_id", ContactRequirementController, :show)

      post(
        "/contact-planning/requirements/:requirement_id/close",
        ContactRequirementController,
        :close
      )

      post(
        "/contact-planning/requirements/:requirement_id/cancel",
        ContactRequirementController,
        :cancel
      )

      post(
        "/contact-planning/requirements/:requirement_id",
        ContactRequirementController,
        :update
      )

      get("/contact-planning/templates/:template_id", ContactTemplateController, :show)
      post("/contact-planning/templates/:template_id", ContactTemplateController, :update)
      # L2: template lifecycle (owner: api).
      post("/contact-planning/templates/:template_id/pause", ContactTemplateController, :pause)

      post(
        "/contact-planning/templates/:template_id/activate",
        ContactTemplateController,
        :activate
      )

      post("/contact-planning/templates/:template_id/close", ContactTemplateController, :close)
      # L3: automation grants (owner: api).
      get("/contact-planning/grants", ContactGrantController, :index)
      post("/contact-planning/grants", ContactGrantController, :create)
      post("/contact-planning/grants/:grant_id/revoke", ContactGrantController, :revoke)
      post("/contact-planning/grants/:grant_id/approve", ContactGrantController, :approve)
      post("/contact-planning/grants/:grant_id/reject", ContactGrantController, :reject)
      post("/contact-planning/grants/:grant_id/narrow", ContactGrantController, :narrow)
      post("/contact-planning/grants/:grant_id/resume", ContactGrantController, :resume)

      post("/contact-plans/:plan_id/execute", ContactPlanController, :execute)

      post(
        "/contact-plans/:plan_id/unconfirmed/:snapshot_id/resolve",
        BookingResolutionController,
        :resolve
      )

      # -- Change sets (owner: api). Contract: docs/apogee/api/changes.md
      scope "/config" do
        get("/", ConfigController, :show)
        post("/stage", ConfigController, :stage)
        post("/preview", ConfigController, :preview_ops)
        get("/change-sets/:change_set_id", ConfigController, :change_set)
        post("/change-sets/:change_set_id/discard", ConfigController, :discard)
        post("/change-sets/:change_set_id/preview", ConfigController, :preview_set)
        post("/change-sets/:change_set_id/submit", ConfigController, :submit)
        post("/change-sets/:change_set_id/review", ConfigController, :review)
        post("/changes/:change_id/withdraw", ConfigController, :withdraw)
        post("/ops/:op_id/rebase", ConfigController, :rebase)
        get("/rollback", ConfigController, :rollback_preview)
        post("/rollback", ConfigController, :rollback)
        get("/revisions", ConfigController, :revisions)
        get("/revisions/:revision", ConfigController, :revision)
        get("/compare", ConfigController, :compare)
        get("/kinds/:kind/schema", ConfigController, :kind_schema)
        # Comms parity 2: the provider-managed transport form's choices and derived preview.
        get(
          "/kinds/transport/provider-options",
          TransportProviderOptionsController,
          :show
        )
      end
    end

    # -- Organization (owner: api). Contracts: docs/apogee/api/setup.md
    scope "/organizations/:organization_id" do
      pipe_through(:console_organization)

      get("/people", PeopleController, :index)
      post("/invitations", PeopleController, :invite)
      put("/people/:user_id", PeopleController, :change_role)
      delete("/people/:user_id", PeopleController, :remove)
      delete("/invitations/:invitation_id", PeopleController, :revoke_invitation)
      post("/invitations/:invitation_id/resend", PeopleController, :resend_invitation)
      get("/service-identities", PeopleController, :service_identities)
      post("/service-identities", ServiceIdentityController, :create)
      post("/service-identities/:service_identity_id/rotate", ServiceIdentityController, :rotate)

      post(
        "/service-identities/:service_identity_id/accountable",
        ServiceIdentityController,
        :accountable
      )

      delete("/service-identities/:service_identity_id", ServiceIdentityController, :revoke)
      get("/missions", OrganizationController, :missions)
      # L4 console mission create (owner: api).
      get("/missions/slug", OrganizationMissionController, :slug)
      post("/missions", OrganizationMissionController, :create)
      get("/audit", OrganizationController, :audit)
      get("/provider-accounts", ProviderAccountController, :index)
      post("/provider-accounts/:id/test", ProviderAccountController, :test)
      get("/provider-accounts/:id/versions", ProviderAccountController, :versions)
      # L13 PA2 detail, grants and credential revoke (owner: api-ops).
      get("/provider-accounts/:id", ProviderAccountGrantController, :show)
      post("/provider-accounts/:id/grants", ProviderAccountGrantController, :grant)

      post(
        "/provider-accounts/:id/grants/:grant_id/revoke",
        ProviderAccountGrantController,
        :revoke_grant
      )

      post(
        "/provider-accounts/:id/credential/revoke",
        ProviderAccountGrantController,
        :revoke_credential
      )

      post("/provider-accounts", ProviderAccountController, :create)
      put("/provider-accounts/:id", ProviderAccountController, :update)
      delete("/provider-accounts/:id", ProviderAccountController, :delete)
      get("/provider-adapters/:key/schema", ProviderAccountController, :schema)
      get("/settings", SettingsController, :show)
      put("/settings/:section_key", SettingsController, :update)
    end

    match(:*, "/*path", NotFoundController, :show)
  end

  scope "/api/cadence/frontend-release/v1", CadenceWeb do
    pipe_through([:api, :frontend_release_publisher])

    put("/objects/:digest", FrontendReleasePublisherController, :upload)
    post("/releases", FrontendReleasePublisherController, :create)
    post("/promotions", FrontendReleasePublisherController, :promote)
  end

  scope "/api/cadence/application-host/v1", CadenceWeb do
    pipe_through([:browser, :require_authenticated_user, :application_host_json])

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
  end

  scope "/api", CadenceWeb do
    pipe_through([:api, :authenticated_api])

    scope "/organizations/:organization_id" do
      scope "/missions/:mission_id" do
        get("/command_stages", CommandStageController, :index)
        post("/command_stages", CommandStageController, :create)
        get("/command_stages/:command_stage_id", CommandStageController, :show)
        patch("/command_stages/:command_stage_id", CommandStageController, :update)

        get("/command_stages/:command_stage_id/items", StagedCommandItemController, :index)
        post("/command_stages/:command_stage_id/items", StagedCommandItemController, :create)

        get("/staged_command_items/:staged_command_item_id", StagedCommandItemController, :show)

        patch(
          "/staged_command_items/:staged_command_item_id",
          StagedCommandItemController,
          :update
        )
      end
    end
  end
end
