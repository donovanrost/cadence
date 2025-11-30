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
        {CadenceWeb.LiveAuth, :put_current_path}
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

    live_session :authenticated,
      layout: {CadenceWeb.Layouts, :sidebar},
      on_mount: [
        {CadenceWeb.LiveAuth, :require_authenticated},
        {CadenceWeb.LiveAuth, :require_organization},
        {CadenceWeb.LiveAuth, :put_current_path}
      ],
      session: {CadenceWeb.LiveAuth, :on_session_init, []} do
      live "/missions", MissionLive.Index, :index
      live "/missions/new", MissionLive.Index, :new
      live "/missions/:id/edit", MissionLive.Index, :edit
      live "/missions/:id", MissionLive.Show, :show
      live "/missions/:id/show/edit", MissionLive.Show, :edit

      # Target routes nested under missions
      live "/missions/:id/targets/new", MissionLive.Show, :new_target
      live "/missions/:id/targets/:target_id/edit", MissionLive.Show, :edit_target

      # Interface routes nested under missions
      live "/missions/:id/interfaces/new", MissionLive.Show, :new_interface
      live "/missions/:id/interfaces/:interface_id/edit", MissionLive.Show, :edit_interface

      # Database routes nested under missions
      live "/missions/:id/databases/new", MissionLive.Show, :new_database
      live "/missions/:id/databases/:database_id", MissionLive.Show, :show_database

      # Derived item routes nested under missions
      live "/missions/:id/derived_items/new", MissionLive.Show, :new_derived_item
      live "/missions/:id/derived_items/:derived_item_id/edit", MissionLive.Show, :edit_derived_item

      # Alarm rule routes nested under missions
      live "/missions/:id/alarm_rules/new", MissionLive.Show, :new_alarm_rule
      live "/missions/:id/alarm_rules/:alarm_rule_id/edit", MissionLive.Show, :edit_alarm_rule

      # Protocol management for interfaces
      live "/missions/:id/interfaces/:interface_id/protocols", ProtocolLive.Index, :index
      live "/missions/:id/interfaces/:interface_id/protocols/new", ProtocolLive.Index, :new
      live "/missions/:id/interfaces/:interface_id/protocols/:protocol_id/edit", ProtocolLive.Index, :edit

      # Standalone target routes
      live "/targets", TargetLive.Index, :index
      live "/targets/:id", TargetLive.Show, :show

      # Telemetry display
      live "/missions/:mission_id/telemetry", TelemetryLive.Index, :index

      # Command sender
      live "/missions/:mission_id/commands", CommandLive.Sender, :index

      # Ops Console (main operator interface)
      live "/missions/:mission_id/ops", OpsConsoleLive.Index, :index
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
