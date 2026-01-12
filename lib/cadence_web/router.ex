defmodule CadenceWeb.Router do
  use CadenceWeb, :router

  import CadenceWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CadenceWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CadenceWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # System Admin Routes
  scope "/admin", CadenceWeb do
    pipe_through [:browser, :require_authenticated_user, :require_system_admin]

    live_session :admin,
      layout: {CadenceWeb.Layouts, :sidebar},
      on_mount: [
        {CadenceWeb.LiveAuth, :require_authenticated},
        {CadenceWeb.LiveAuth, :require_system_admin},
        {CadenceWeb.LiveAuth, :put_current_path},
        {CadenceWeb.LiveAuth, :subscribe_notifications}
      ],
      session: {CadenceWeb.LiveAuth, :on_session_init, []} do
      live "/", AdminLive.Index, :index

      live "/organizations", OrganizationLive.Index, :index
      live "/organizations/new", OrganizationLive.Index, :new
      live "/organizations/:id/edit", OrganizationLive.Index, :edit
      live "/organizations/:id", OrganizationLive.Show, :show
      live "/organizations/:id/show/edit", OrganizationLive.Show, :edit
      live "/organizations/:id/members", AdminLive.OrganizationMembers, :index

      # Design system documentation
      live "/design-system", DesignSystemLive.Index, :index

      # User management routes (TODO: implement these LiveViews)
      # live "/users", UserLive.Index, :index
      # live "/users/:id", UserLive.Show, :show

      # Invitation management routes (TODO: implement these LiveViews)
      # live "/invitations", InvitationLive.Index, :index
      # live "/invitations/new", InvitationLive.Index, :new
    end
  end

  # Authenticated User Routes (require organization context)
  scope "/", CadenceWeb do
    pipe_through [:browser, :require_authenticated_user, :require_organization]

    # General authenticated routes (organization sidebar)
    live_session :authenticated,
      layout: {CadenceWeb.Layouts, :sidebar},
      on_mount: [
        {CadenceWeb.LiveAuth, :require_authenticated},
        {CadenceWeb.LiveAuth, :require_organization},
        {CadenceWeb.LiveAuth, :put_current_path},
        {CadenceWeb.LiveAuth, :subscribe_notifications}
      ],
      session: {CadenceWeb.LiveAuth, :on_session_init, []} do
      live "/missions", MissionLive.Index, :index
      live "/missions/new", MissionLive.Index, :new
      live "/missions/:id/edit", MissionLive.Index, :edit

      # Standalone target routes
      live "/targets", TargetLive.Index, :index
      live "/targets/:id", TargetLive.Show, :show

      # Organization settings
      live "/settings", SettingsLive.Index, :index
      live "/settings/procedures", SettingsLive.Index, :procedures

      # Notifications
      live "/notifications", NotificationLive.Index, :index

      # Global Reviews Inbox
      live "/reviews", ReviewLive.Index, :index
    end

    # Mission-specific routes (mission sidebar with mission context)
    live_session :mission,
      layout: {CadenceWeb.Layouts, :mission_sidebar},
      on_mount: [
        {CadenceWeb.LiveAuth, :require_authenticated},
        {CadenceWeb.LiveAuth, :require_organization},
        {CadenceWeb.LiveAuth, :put_current_path},
        {CadenceWeb.LiveAuth, :load_mission}
      ],
      session: {CadenceWeb.LiveAuth, :on_session_init, []} do
      # Mission overview
      live "/missions/:id", MissionLive.Show, :show
      live "/missions/:id/show/edit", MissionLive.Show, :edit

      # Target routes nested under missions
      live "/missions/:id/targets", MissionLive.Targets, :index
      live "/missions/:id/targets/new", MissionLive.Targets, :new
      live "/missions/:id/targets/:target_id/edit", MissionLive.Targets, :edit

      # Interface routes nested under missions
      live "/missions/:id/interfaces", MissionLive.Interfaces, :index
      live "/missions/:id/interfaces/new", MissionLive.Interfaces, :new
      live "/missions/:id/interfaces/:interface_id/edit", MissionLive.Interfaces, :edit
      live "/missions/:id/interfaces/:interface_id", MissionLive.InterfaceShow, :show

      live "/missions/:id/interfaces/:interface_id/vcids/new",
           MissionLive.InterfaceShow,
           :new_vcid

      live "/missions/:id/interfaces/:interface_id/vcids/:vcid_id/edit",
           MissionLive.InterfaceShow,
           :edit_vcid

      live "/missions/:id/interfaces/:interface_id/targets/:target_interface_id/scid/edit",
           MissionLive.InterfaceShow,
           :edit_scid

      # Protocol management for interfaces
      live "/missions/:id/interfaces/:interface_id/protocols", ProtocolLive.Index, :index
      live "/missions/:id/interfaces/:interface_id/protocols/new", ProtocolLive.Index, :new

      live "/missions/:id/interfaces/:interface_id/protocols/:protocol_id/edit",
           ProtocolLive.Index,
           :edit

      # Database catalog section (database and version management)
      live "/missions/:id/database", MissionLive.Database, :index
      live "/missions/:id/database/new", MissionLive.Database, :new_database
      live "/missions/:id/database/:database_id", MissionLive.Database, :show_database
      live "/missions/:id/database/:database_id/edit", MissionLive.Database, :edit_database
      live "/missions/:id/database/:database_id/import", MissionLive.Database, :import

      live "/missions/:id/database/:database_id/versions/:version_id",
           MissionLive.Database,
           :show_version

      # Catalog section (search/browse telemetry, commands, derived)
      live "/missions/:id/catalog", MissionLive.Catalog, :index
      live "/missions/:id/catalog/derived/new", MissionLive.Catalog, :new_derived
      live "/missions/:id/catalog/derived/:derived_id/edit", MissionLive.Catalog, :edit_derived

      # Alarm rules section
      live "/missions/:id/alarms", MissionLive.Alarms, :index
      live "/missions/:id/alarms/new", MissionLive.Alarms, :new
      live "/missions/:id/alarms/:alarm_rule_id/edit", MissionLive.Alarms, :edit

      # Command sender
      live "/missions/:id/commands", CommandLive.Sender, :index

      # Procedures - List View
      live "/missions/:id/procedures", MissionLive.Procedures.Index, :index

      # Procedures - Reviews (mission-scoped review inbox)
      live "/missions/:id/procedures/reviews", MissionLive.Procedures.Reviews, :index

      # Procedures - Detail View with Tabs
      live "/missions/:id/procedures/:procedure_id", MissionLive.Procedures.Show, :overview

      live "/missions/:id/procedures/:procedure_id/versions",
           MissionLive.Procedures.Show,
           :versions

      live "/missions/:id/procedures/:procedure_id/executions",
           MissionLive.Procedures.Show,
           :executions

      live "/missions/:id/procedures/:procedure_id/reviews", MissionLive.Procedures.Show, :reviews
      live "/missions/:id/procedures/:procedure_id/execute", MissionLive.Procedures.Show, :execute

      # Procedures V2 - Block-based editor & execution
      live "/missions/:id/procedures-v2/:procedure_id/versions/:version_id/edit",
           ProcedureV2Live.VersionEdit,
           :edit_version

      # Review workflow - Overview and Changes tabs
      live "/missions/:id/procedures-v2/:procedure_id/versions/:version_id/review",
           ReviewLive.Overview,
           :overview

      live "/missions/:id/procedures-v2/:procedure_id/versions/:version_id/review/changes",
           ReviewLive.Changes,
           :changes

      live "/missions/:id/procedures-v2/:procedure_id/executions/:execution_id",
           ProcedureV2Live.ExecutionShow,
           :show_execution

      # Automations
      live "/missions/:id/automations", MissionLive.Automations, :index
      live "/missions/:id/automations/new", MissionLive.Automations, :new
      live "/missions/:id/automations/:automation_id/edit", MissionLive.Automations, :edit

      # Schedules
      live "/missions/:id/schedules", MissionLive.Schedules, :index
      live "/missions/:id/schedules/new", MissionLive.Schedules, :new
      live "/missions/:id/schedules/:schedule_id/edit", MissionLive.Schedules, :edit

      # Mission Settings
      live "/missions/:id/settings", MissionLive.Settings, :index
      live "/missions/:id/settings/procedures", MissionLive.Settings, :procedures
    end

    # Ops Console - Mission control interface
    live_session :ops_console,
      layout: {CadenceWeb.Layouts, :ops_console},
      on_mount: [
        {CadenceWeb.LiveAuth, :require_authenticated},
        {CadenceWeb.LiveAuth, :require_organization},
        {CadenceWeb.LiveAuth, :load_mission}
      ],
      session: {CadenceWeb.LiveAuth, :on_session_init, []} do
      # Dashboard mode (GridStack widgets)
      live "/missions/:id/ops", OpsConsoleLive.Index, :dashboard

      # Commands mode
      live "/missions/:id/ops/commands", OpsConsoleLive.Commands, :index

      # Queue mode
      live "/missions/:id/ops/queue", OpsConsoleLive.Queue, :overview
      live "/missions/:id/ops/queue/manage", OpsConsoleLive.Queue, :manage
      live "/missions/:id/ops/queue/table", OpsConsoleLive.Queue, :table

      # Alarms mode
      live "/missions/:id/ops/alarms", OpsConsoleLive.Alarms, :active
      live "/missions/:id/ops/alarms/panel", OpsConsoleLive.Alarms, :panel
      live "/missions/:id/ops/alarms/history", OpsConsoleLive.Alarms, :historical
      live "/missions/:id/ops/alarms/rules", OpsConsoleLive.Alarms, :rules
      live "/missions/:id/ops/alarms/analytics", OpsConsoleLive.Alarms, :analytics

      # Timeline mode
      live "/missions/:id/ops/timeline", OpsConsoleLive.Timeline, :stream
      live "/missions/:id/ops/timeline/matrix", OpsConsoleLive.Timeline, :matrix
      live "/missions/:id/ops/timeline/lanes", OpsConsoleLive.Timeline, :lanes
    end
  end

  # User Profile routes (authentication required, no organization required)
  scope "/", CadenceWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :profile,
      layout: {CadenceWeb.Layouts, :profile_sidebar},
      on_mount: [
        {CadenceWeb.LiveAuth, :require_authenticated},
        {CadenceWeb.LiveAuth, :put_current_path}
      ],
      session: {CadenceWeb.LiveAuth, :on_session_init, []} do
      live "/profile", ProfileLive.Index, :index
      live "/profile/email", ProfileLive.Email, :index
      live "/profile/appearance", ProfileLive.Appearance, :index
      live "/profile/notifications", NotificationLive.Preferences, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", CadenceWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cadence, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CadenceWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", CadenceWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", CadenceWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", CadenceWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
