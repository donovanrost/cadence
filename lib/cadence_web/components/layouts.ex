defmodule CadenceWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CadenceWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders a sidebar layout with navigation.

  ## Examples

      <Layouts.sidebar flash={@flash} current_scope={@current_scope} current_path={@current_uri} inner_content={@inner_content}>
      </Layouts.sidebar>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :inner_content, :any, required: true

  def sidebar(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <!-- Page content -->
        <div class="flex flex-col h-screen">
          <!-- Top bar with page title and user menu (visible when sidebar is hidden on mobile) -->
          <div class="lg:hidden flex items-center justify-between p-4 border-b border-base-300">
            <label for="sidebar-drawer" class="btn btn-ghost drawer-button">
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </label>
            <div class="flex-1 text-center font-semibold text-lg">CADENCE</div>
            <.user_org_menu id="user-org-menu-mobile" current_scope={@current_scope} />
          </div>
          
    <!-- Main content area -->
          <main class="flex-1 overflow-y-auto bg-base-100">
            <!-- Desktop: User menu in top-right -->
            <div class="hidden lg:flex justify-end p-4 border-b border-base-300">
              <.user_org_menu id="user-org-menu-desktop" current_scope={@current_scope} />
            </div>
            
    <!-- Page content -->
            <div class="p-6">
              {@inner_content}
            </div>
          </main>
        </div>
      </div>
      
    <!-- Sidebar -->
      <div class="drawer-side">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div class="min-h-full w-72 bg-base-200 dark:sidebar-dark-bg flex flex-col border-r border-base-300">
          <!-- Logo/Brand -->
          <div class="p-6 border-b border-base-300">
            <.link navigate={~p"/"} class="flex items-center gap-3">
              <img src={~p"/images/logo.svg"} width="32" class="glow-cyan" />
              <span class="text-xl font-bold tracking-wide gradient-vaporwave bg-clip-text text-transparent">
                CADENCE
              </span>
            </.link>
          </div>
          
    <!-- Navigation -->
          <nav class="flex-1 overflow-y-auto p-4">
            <ul class="menu space-y-1">
              <.sidebar_navigation current_scope={@current_scope} current_path={@current_path} />
            </ul>
          </nav>
          
    <!-- Theme toggle at bottom -->
          <div class="p-4 border-t border-base-300">
            <.theme_toggle />
          </div>
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders navigation items based on current context (admin vs org).
  """
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""

  def sidebar_navigation(assigns) do
    is_admin_context = String.starts_with?(assigns.current_path, "/admin")

    assigns = assign(assigns, :is_admin_context, is_admin_context)

    ~H"""
    <%= if @is_admin_context do %>
      <!-- System Admin Navigation -->
      <.sidebar_nav_item navigate={~p"/admin"} active={@current_path == "/admin"}>
        <:icon><.icon name="hero-home" class="h-5 w-5" /></:icon>
        Dashboard
      </.sidebar_nav_item>

      <.sidebar_nav_item
        navigate={~p"/admin/organizations"}
        active={String.contains?(@current_path, "/admin/organizations")}
      >
        <:icon><.icon name="hero-building-office" class="h-5 w-5" /></:icon>
        Organizations
      </.sidebar_nav_item>

      <.sidebar_nav_item
        navigate={~p"/admin/design-system"}
        active={String.contains?(@current_path, "/admin/design-system")}
      >
        <:icon><.icon name="hero-paint-brush" class="h-5 w-5" /></:icon>
        Design System
      </.sidebar_nav_item>

      <%!-- TODO: Uncomment when these pages are implemented
      <.sidebar_nav_item
        navigate={~p"/admin/users"}
        active={String.contains?(@current_path, "/admin/users")}
      >
        <:icon><.icon name="hero-users" class="h-5 w-5" /></:icon>
        Users
      </.sidebar_nav_item>

      <.sidebar_nav_item
        navigate={~p"/admin/invitations"}
        active={String.contains?(@current_path, "/admin/invitations")}
      >
        <:icon><.icon name="hero-envelope" class="h-5 w-5" /></:icon>
        Invitations
      </.sidebar_nav_item>
      --%>
    <% else %>
      <!-- Organization/Mission Navigation -->
      <.sidebar_nav_item navigate={~p"/"} active={@current_path == "/"}>
        <:icon><.icon name="hero-home" class="h-5 w-5" /></:icon>
        Dashboard
      </.sidebar_nav_item>

      <.sidebar_nav_item
        navigate={~p"/missions"}
        active={String.contains?(@current_path, "/missions")}
      >
        <:icon><.icon name="hero-rocket-launch" class="h-5 w-5" /></:icon>
        Missions
      </.sidebar_nav_item>

      <.sidebar_nav_item
        navigate={~p"/targets"}
        active={String.contains?(@current_path, "/targets")}
      >
        <:icon><.icon name="hero-signal" class="h-5 w-5" /></:icon>
        Targets
      </.sidebar_nav_item>

      <.sidebar_nav_item navigate={~p"/team"} active={String.contains?(@current_path, "/team")}>
        <:icon><.icon name="hero-user-group" class="h-5 w-5" /></:icon>
        Team
      </.sidebar_nav_item>

      <.sidebar_nav_item
        navigate={~p"/settings"}
        active={String.contains?(@current_path, "/settings")}
      >
        <:icon><.icon name="hero-cog-6-tooth" class="h-5 w-5" /></:icon>
        Settings
      </.sidebar_nav_item>
    <% end %>
    """
  end

  @doc """
  Renders the combined user/org menu dropdown.
  """
  attr :id, :string, required: true
  attr :current_scope, :map, required: true

  def user_org_menu(assigns) do
    user = assigns.current_scope.user
    current_org = assigns.current_scope.current_organization
    all_orgs = assigns.current_scope.all_organizations || []
    is_system_admin = assigns.current_scope.system_admin?

    org_name =
      if current_org do
        current_org.name
      else
        if is_system_admin, do: "System Admin", else: "No Organization"
      end

    assigns =
      assigns
      |> assign(:user, user)
      |> assign(:current_org, current_org)
      |> assign(:all_orgs, all_orgs)
      |> assign(:is_system_admin, is_system_admin)
      |> assign(:org_name, org_name)

    ~H"""
    <.dropdown id={@id}>
      <:trigger>
        <div class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-base-200 cursor-pointer transition-glow hover-glow-cyan">
          <.avatar email={@user.email} size="sm" />
          <div class="hidden sm:flex flex-col items-start">
            <span class="text-sm font-semibold">{@org_name}</span>
            <span class="text-xs text-base-content/60">{@user.email}</span>
          </div>
          <.icon name="hero-chevron-down" class="h-4 w-4 hidden sm:block" />
        </div>
      </:trigger>
      
    <!-- Organizations Section -->
      <%= if @all_orgs != [] do %>
        <li class="menu-title px-4 py-2">
          <span class="text-xs uppercase tracking-wide text-base-content/50">Organizations</span>
        </li>
        <%= for org <- @all_orgs do %>
          <li>
            <.link navigate={~p"/org/#{org.slug}"} class="hover-glow-cyan transition-glow">
              <div class="flex items-center justify-between w-full">
                <span>{org.name}</span>
                <%= if @current_org && org.id == @current_org.id do %>
                  <.icon name="hero-check" class="h-4 w-4 text-primary" />
                <% end %>
              </div>
            </.link>
          </li>
        <% end %>
        <li class="border-t border-base-300 my-1"></li>
      <% end %>
      
    <!-- User Actions -->
      <li>
        <.link navigate={~p"/settings/account"} class="hover-glow-cyan transition-glow">
          <.icon name="hero-user" class="h-4 w-4" /> Your Profile
        </.link>
      </li>

      <li>
        <.link navigate={~p"/settings"} class="hover-glow-cyan transition-glow">
          <.icon name="hero-cog-6-tooth" class="h-4 w-4" /> Account Settings
        </.link>
      </li>
      
    <!-- System Admin Link -->
      <%= if @is_system_admin do %>
        <li class="border-t border-base-300 my-1"></li>
        <li>
          <.link navigate={~p"/admin/organizations"} class="hover-glow-cyan transition-glow">
            <.icon name="hero-shield-check" class="h-4 w-4" />
            <span class="font-semibold text-accent">Admin Panel</span>
          </.link>
        </li>
      <% end %>

      <li class="border-t border-base-300 my-1"></li>

      <li>
        <a href={~p"/users/log_out"} data-method="delete" class="hover-glow-cyan transition-glow">
          <.icon name="hero-arrow-right-on-rectangle" class="h-4 w-4" /> Sign Out
        </a>
      </li>
    </.dropdown>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a full-screen layout for the Ops Console.

  No sidebar or header - the entire viewport is used by the application.
  """
  attr :flash, :map, required: true
  attr :inner_content, :any, required: true

  def ops_console(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden">
      {@inner_content}
    </div>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders a sidebar layout with mission-specific navigation.

  This layout is used for all mission detail pages and includes
  a secondary navigation for mission sub-sections.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :mission, :map, default: nil
  attr :inner_content, :any, required: true

  def mission_sidebar(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <!-- Page content -->
        <div class="flex flex-col h-screen">
          <!-- Top bar (mobile) -->
          <div class="lg:hidden flex items-center justify-between p-4 border-b border-base-300">
            <label for="sidebar-drawer" class="btn btn-ghost drawer-button">
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </label>
            <div class="flex-1 text-center font-semibold text-lg">
              {if @mission, do: @mission.name, else: "CADENCE"}
            </div>
            <.user_org_menu id="user-org-menu-mobile" current_scope={@current_scope} />
          </div>
          
    <!-- Main content area -->
          <main class="flex-1 overflow-y-auto bg-base-100">
            <!-- Desktop: User menu in top-right -->
            <div class="hidden lg:flex justify-end p-4 border-b border-base-300">
              <.user_org_menu id="user-org-menu-desktop" current_scope={@current_scope} />
            </div>
            
    <!-- Page content -->
            <div class="p-6">
              {@inner_content}
            </div>
          </main>
        </div>
      </div>
      
    <!-- Sidebar -->
      <div class="drawer-side">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div class="min-h-full w-72 bg-base-200 dark:sidebar-dark-bg flex flex-col border-r border-base-300">
          <!-- Logo/Brand -->
          <div class="p-6 border-b border-base-300">
            <.link navigate={~p"/"} class="flex items-center gap-3">
              <img src={~p"/images/logo.svg"} width="32" class="glow-cyan" />
              <span class="text-xl font-bold tracking-wide gradient-vaporwave bg-clip-text text-transparent">
                CADENCE
              </span>
            </.link>
          </div>
          
    <!-- Back to missions link -->
          <div class="px-4 py-3 border-b border-base-300">
            <.link
              navigate={~p"/missions"}
              class="flex items-center gap-2 text-sm text-base-content/60 hover:text-base-content transition-colors"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" />
              <span>All Missions</span>
            </.link>
          </div>
          
    <!-- Mission Header -->
          <%= if @mission do %>
            <div class="px-4 py-4 border-b border-base-300">
              <div class="flex items-center gap-3">
                <div class="flex-1 min-w-0">
                  <h2 class="font-semibold text-base truncate">{@mission.name}</h2>
                  <div class="flex items-center gap-2 mt-1">
                    <span class={[
                      "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                      @mission.status == "active" && "bg-success/20 text-success",
                      @mission.status == "inactive" && "bg-base-300 text-base-content/60",
                      @mission.status == "suspended" && "bg-error/20 text-error"
                    ]}>
                      {@mission.status}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          
    <!-- Mission Navigation -->
          <nav class="flex-1 overflow-y-auto p-4">
            <ul class="menu space-y-1">
              <.mission_navigation mission={@mission} current_path={@current_path} />
            </ul>
          </nav>
          
    <!-- Theme toggle at bottom -->
          <div class="p-4 border-t border-base-300">
            <.theme_toggle />
          </div>
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders mission-specific navigation items.
  """
  attr :mission, :map, required: true
  attr :current_path, :string, default: ""

  def mission_navigation(assigns) do
    # Determine which section is active based on path
    mission_id = if assigns.mission, do: assigns.mission.id, else: nil

    # Build path patterns for matching
    base_path = if mission_id, do: "/missions/#{mission_id}", else: ""

    assigns =
      assigns
      |> assign(:base_path, base_path)
      |> assign(
        :is_overview,
        assigns.current_path == base_path or assigns.current_path == "#{base_path}/show/edit"
      )
      |> assign(:is_targets, String.contains?(assigns.current_path, "#{base_path}/targets"))
      |> assign(:is_interfaces, String.contains?(assigns.current_path, "#{base_path}/interfaces"))
      |> assign(:is_database, String.contains?(assigns.current_path, "#{base_path}/database"))
      |> assign(:is_catalog, String.contains?(assigns.current_path, "#{base_path}/catalog"))
      |> assign(:is_alarms, String.contains?(assigns.current_path, "#{base_path}/alarm"))
      |> assign(:is_commands, String.contains?(assigns.current_path, "#{base_path}/commands"))
      |> assign(:is_procedures, String.contains?(assigns.current_path, "#{base_path}/procedures"))
      |> assign(
        :is_automations,
        String.contains?(assigns.current_path, "#{base_path}/automations")
      )
      |> assign(:is_schedules, String.contains?(assigns.current_path, "#{base_path}/schedules"))

    ~H"""
    <%= if @mission do %>
      <.sidebar_nav_item navigate={~p"/missions/#{@mission}"} active={@is_overview}>
        <:icon><.icon name="hero-squares-2x2" class="h-5 w-5" /></:icon>
        Overview
      </.sidebar_nav_item>

      <.sidebar_nav_item navigate={~p"/missions/#{@mission}/targets"} active={@is_targets}>
        <:icon><.icon name="hero-cpu-chip" class="h-5 w-5" /></:icon>
        Targets
      </.sidebar_nav_item>

      <.sidebar_nav_item navigate={~p"/missions/#{@mission}/interfaces"} active={@is_interfaces}>
        <:icon><.icon name="hero-signal" class="h-5 w-5" /></:icon>
        Interfaces
      </.sidebar_nav_item>

      <.sidebar_nav_group
        label="Database"
        icon="hero-circle-stack"
        expanded={@is_database or @is_catalog}
      >
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/database"} active={@is_database}>
          Versions
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/catalog"} active={@is_catalog}>
          Catalog
        </.sidebar_nav_child>
      </.sidebar_nav_group>

      <.sidebar_nav_item navigate={~p"/missions/#{@mission}/alarms"} active={@is_alarms}>
        <:icon><.icon name="hero-bell-alert" class="h-5 w-5" /></:icon>
        Alarms
      </.sidebar_nav_item>

      <.sidebar_nav_item navigate={~p"/missions/#{@mission}/commands"} active={@is_commands}>
        <:icon><.icon name="hero-command-line" class="h-5 w-5" /></:icon>
        Commands
      </.sidebar_nav_item>

      <.sidebar_nav_group
        label="Procedures"
        icon="hero-document-text"
        expanded={@is_procedures or @is_automations or @is_schedules}
      >
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/procedures"} active={@is_procedures}>
          Procedures
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/automations"} active={@is_automations}>
          Automations
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/schedules"} active={@is_schedules}>
          Schedules
        </.sidebar_nav_child>
      </.sidebar_nav_group>

      <li class="my-3 border-t border-base-300"></li>

      <.sidebar_nav_item navigate={~p"/missions/#{@mission}/ops"} active={false}>
        <:icon><.icon name="hero-play" class="h-5 w-5" /></:icon>
        <span class="flex items-center gap-2">
          Ops Console <span class="badge badge-xs badge-primary">Live</span>
        </span>
      </.sidebar_nav_item>
    <% end %>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
