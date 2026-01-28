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

  attr :variant, :atom,
    default: :standard,
    doc: "layout style: :standard renders header/main, :bare renders only content"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @variant == :standard do %>
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
    <% else %>
      {render_slot(@inner_block)}
    <% end %>

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
  attr :notifications, :list, default: []
  attr :notification_unread_count, :integer, default: 0
  attr :review_pending_count, :integer, default: 0
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
            <div class="flex items-center gap-2">
              <CadenceWeb.NotificationComponents.notification_bell
                id="notification-bell-mobile"
                unread_count={@notification_unread_count}
                notifications={@notifications}
              />
              <.user_org_menu id="user-org-menu-mobile" current_scope={@current_scope} />
            </div>
          </div>
          
    <!-- Desktop: Fixed top bar (outside main, doesn't scroll) -->
          <div class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0">
            <CadenceWeb.NotificationComponents.notification_bell
              id="notification-bell-desktop"
              unread_count={@notification_unread_count}
              notifications={@notifications}
            />
            <.user_org_menu id="user-org-menu-desktop" current_scope={@current_scope} size="sm" />
          </div>
          
    <!-- Main content area -->
          <main class="flex-1 overflow-y-auto bg-base-100">
            <div class="p-6">
              {@inner_content}
            </div>
          </main>
        </div>
      </div>
      
    <!-- Sidebar - HUD Mission Control Style -->
      <div class="drawer-side">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div
          data-sidebar-collapsible
          class="sidebar-collapsible sidebar-expanded min-h-full bg-base-200 dark:sidebar-dark-bg flex flex-col border-r border-primary/20 hud-grid relative"
        >
          <!-- Logo/Brand (h-10 matches top bar height) -->
          <div class="px-3 h-10 flex items-center border-b border-primary/20">
            <.link navigate={~p"/"} class="flex items-center gap-2">
              <div class="relative flex-shrink-0">
                <img src={~p"/images/logo.svg"} width="20" class="relative z-10" />
                <div class="absolute inset-0 blur-md bg-primary/30"></div>
              </div>
              <span class="text-xs font-bold tracking-[0.15em] text-primary sidebar-label">
                CADENCE
              </span>
            </.link>
          </div>
          
    <!-- Navigation -->
          <nav class="flex-1 overflow-y-auto py-2">
            <div class="px-3 mb-2 sidebar-expanded-only">
              <span class="hud-label text-base-content/30">Navigation</span>
            </div>
            <ul class="menu menu-sm space-y-0.5">
              <.sidebar_navigation
                current_scope={@current_scope}
                current_path={@current_path}
                review_pending_count={@review_pending_count}
              />
            </ul>
          </nav>
          
    <!-- Toggle Button -->
          <button
            type="button"
            class="sidebar-toggle-btn hidden lg:flex"
            phx-click={JS.dispatch("phx:toggle-sidebar")}
            title="Toggle sidebar"
          >
            <.icon name="hero-chevron-left" class="h-3 w-3 toggle-chevron transition-transform" />
          </button>
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
  attr :review_pending_count, :integer, default: 0

  def sidebar_navigation(assigns) do
    is_admin_context = String.starts_with?(assigns.current_path, "/admin")

    # Check for settings sub-routes
    is_settings = String.contains?(assigns.current_path, "/settings")
    is_settings_general = assigns.current_path == "/settings"
    is_settings_procedures = assigns.current_path == "/settings/procedures"

    assigns =
      assigns
      |> assign(:is_admin_context, is_admin_context)
      |> assign(:is_settings, is_settings)
      |> assign(:is_settings_general, is_settings_general)
      |> assign(:is_settings_procedures, is_settings_procedures)

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

      <.sidebar_nav_group
        label="Settings"
        icon="hero-cog-6-tooth"
        expanded={@is_settings}
      >
        <.sidebar_nav_child navigate={~p"/settings"} active={@is_settings_general}>
          General
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/settings/procedures"} active={@is_settings_procedures}>
          Procedures
        </.sidebar_nav_child>
      </.sidebar_nav_group>

      <%!-- TODO: Uncomment when team management is implemented
      <.sidebar_nav_item navigate={~p"/team"} active={String.contains?(@current_path, "/team")}>
        <:icon><.icon name="hero-user-group" class="h-5 w-5" /></:icon>
        Team
      </.sidebar_nav_item>
      --%>
    <% end %>
    """
  end

  @doc """
  Renders the combined user/org menu dropdown.
  """
  attr :id, :string, required: true
  attr :current_scope, :map, required: true
  attr :size, :string, default: "md", values: ~w(sm md)

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
        <div class={[
          "flex items-center rounded-lg hover:bg-base-200 cursor-pointer transition-glow hover-glow-cyan",
          @size == "sm" && "gap-2 px-2 py-1",
          @size == "md" && "gap-3 px-3 py-2"
        ]}>
          <.avatar email={@user.email} size={if @size == "sm", do: "xs", else: "sm"} />
          <div class="hidden sm:flex flex-col items-start">
            <span class={["font-semibold", @size == "sm" && "text-xs", @size == "md" && "text-sm"]}>
              {@org_name}
            </span>
            <span :if={@size == "md"} class="text-xs text-base-content/60">{@user.email}</span>
          </div>
          <.icon name="hero-chevron-down" class={chevron_class(@size)} />
        </div>
      </:trigger>

      <%!-- TODO: Uncomment when org switcher routes are implemented
      <!-- Organizations Section -->
      <%= if @all_orgs != [] do %>
        <li class="menu-title px-4 py-2">
          <span class="text-xs uppercase tracking-wide text-base-content/50">Organizations</span>
        </li>
        <%= for org <- @all_orgs do %>
          <li>
            <.link navigate={"/org/#{org.slug}"} class="hover-glow-cyan transition-glow">
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
      --%>
      
    <!-- User Actions -->
      <li>
        <.link navigate={~p"/users/settings"} class="hover-glow-cyan transition-glow">
          <.icon name="hero-user" class="h-4 w-4" /> Your Profile
        </.link>
      </li>

      <li>
        <.link navigate={~p"/users/settings"} class="hover-glow-cyan transition-glow">
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
        <.link href={~p"/users/log-out"} method="delete" class="hover-glow-cyan transition-glow">
          <.icon name="hero-arrow-right-on-rectangle" class="h-4 w-4" /> Sign Out
        </.link>
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
      <.flash kind={:success} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
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
  Renders a minimal full-screen layout for the Ops Console dashboard.

  No sidebar or header - the entire viewport is used by the application.
  Used by Index (dashboard mode) which renders its own layout via JS hook.
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
  Renders a full-screen layout for Ops Console modes (Commands, Queue, Alarms, Timeline).

  A three-column layout with:
  - Nav panel (left) - mode navigation
  - Main content (center) - mode-specific content
  - Context panel (right) - alarms and queue summary

  The layout uses LiveComponents for the panels to enable real-time updates.
  """
  attr :flash, :map, required: true
  attr :mission, :map, required: true
  attr :current_scope, :map, required: true
  attr :alarm_counts, :map, default: %{critical: 0, warning: 0, info: 0}
  attr :alarms, :list, default: []
  attr :queue_entries, :list, default: []
  attr :targets, :list, default: []
  attr :current_time, :any, default: nil
  attr :dashboards, :list, default: []
  attr :fleet_health, :map, default: %{}
  attr :running_procedures, :list, default: []
  attr :current_mode, :atom, default: :dashboard
  attr :current_dashboard_id, :any, default: nil
  attr :inner_content, :any, required: true

  def ops_console_mode(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden bg-base-100 flex flex-col">
      <!-- Global Status Bar -->
      <.live_component
        module={CadenceWeb.OpsConsoleLive.StatusBarComponent}
        id="status-bar"
        mission={@mission}
        alarm_counts={@alarm_counts}
        fleet_health={@fleet_health}
        running_procedures={@running_procedures}
        current_time={@current_time || DateTime.utc_now()}
      />
      <!-- Main layout using panel-layout CSS classes for consistent styling -->
      <div
        class="panel-layout flex-1"
        id="mode-panel-layout"
        phx-hook=".PanelResize"
        data-mission-id={@mission.id}
      >
        <!-- Nav Panel -->
        <aside class="panel-nav" id="panel-nav">
          <div class="panel-content h-full overflow-y-auto">
            <.live_component
              module={CadenceWeb.OpsConsoleLive.NavPanelComponent}
              id="nav-panel"
              mission={@mission}
              dashboards={@dashboards}
              current_mode={@current_mode}
              current_dashboard_id={@current_dashboard_id}
            />
          </div>
          <!-- Resize handle for nav panel -->
          <div class="panel-resize-handle panel-resize-right" data-panel="navigation"></div>
          <!-- Toggle button -->
          <button
            class="panel-toggle panel-toggle-nav"
            data-panel="navigation"
            title="Toggle Navigation"
          >
            <svg
              class="toggle-icon"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M15 18l-6-6 6-6" />
            </svg>
          </button>
        </aside>
        <!-- Main Content Area -->
        <main class="panel-main">
          {@inner_content}
        </main>
        <!-- Context Panel -->
        <aside class="panel-context" id="panel-context">
          <!-- Toggle button -->
          <button
            class="panel-toggle panel-toggle-context"
            data-panel="context"
            title="Toggle Context"
          >
            <svg
              class="toggle-icon"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M9 18l6-6-6-6" />
            </svg>
          </button>
          <!-- Resize handle for context panel -->
          <div class="panel-resize-handle panel-resize-left" data-panel="context"></div>
          <div class="panel-content h-full overflow-y-auto">
            <.live_component
              module={CadenceWeb.OpsConsoleLive.ContextPanelComponent}
              id="context-panel"
              mission={@mission}
              alarm_counts={@alarm_counts}
              alarms={@alarms}
              queue_entries={@queue_entries}
              targets={@targets}
            />
          </div>
        </aside>
        <!-- Inline script to apply saved panel state before first paint (prevents flash) -->
        <script>
          (function() {
            try {
              var layout = document.getElementById('mode-panel-layout');
              var missionId = layout && layout.dataset.missionId || 'default';
              var saved = localStorage.getItem('ops-mode-panels-' + missionId);
              if (saved) {
                var state = JSON.parse(saved);
                var nav = document.getElementById('panel-nav');
                var ctx = document.getElementById('panel-context');
                if (state.navigation && nav) {
                  nav.style.width = state.navigation.width + 'px';
                  if (!state.navigation.open) nav.classList.add('collapsed');
                }
                if (state.context && ctx) {
                  ctx.style.width = state.context.width + 'px';
                  if (!state.context.open) ctx.classList.add('collapsed');
                }
              }
            } catch (e) {}
          })();
        </script>
      </div>
    </div>
    <.flash_group flash={@flash} />

    <script :type={Phoenix.LiveView.ColocatedHook} name=".PanelResize">
      export default {
        mounted() {
          this.config = {
            navigation: {
              openWidth: 220,
              closedWidth: 48,
              snapThreshold: 120,
              minDragWidth: 48,
              maxDragWidth: 300,
              side: 'left'
            },
            context: {
              openWidth: 260,
              closedWidth: 52,
              snapThreshold: 140,
              minDragWidth: 52,
              maxDragWidth: 400,
              side: 'right'
            }
          }

          this.panelStates = {
            navigation: { open: true, width: this.config.navigation.openWidth },
            context: { open: true, width: this.config.context.openWidth }
          }

          this.isDragging = false
          this.dragPanel = null
          this.dragStartX = 0
          this.dragStartWidth = 0
          this.navPanel = this.el.querySelector('#panel-nav')
          this.contextPanel = this.el.querySelector('#panel-context')
          this.storageKey = `ops-mode-panels-${this.el.dataset.missionId || 'default'}`

          this.loadState()
          this.applyPanelStates()
          this.bindResizeHandlers()
          this.bindToggleButtons()
          this.bindRailClickHandlers()
        },

        updated() {
          // Re-apply saved panel states after LiveView updates
          // This preserves panel width and collapsed state when content updates
          this.applyPanelStates()
        },

        loadState() {
          try {
            const saved = localStorage.getItem(this.storageKey)
            if (saved) {
              const parsed = JSON.parse(saved)
              if (parsed.navigation) {
                this.panelStates.navigation = { ...this.panelStates.navigation, ...parsed.navigation }
              }
              if (parsed.context) {
                this.panelStates.context = { ...this.panelStates.context, ...parsed.context }
              }
            }
          } catch (e) {
            console.warn('[PanelResize] Failed to load panel state:', e)
          }
        },

        saveState() {
          try {
            localStorage.setItem(this.storageKey, JSON.stringify(this.panelStates))
          } catch (e) {
            console.warn('[PanelResize] Failed to save panel state:', e)
          }
        },

        bindResizeHandlers() {
          const handles = this.el.querySelectorAll('.panel-resize-handle')
          handles.forEach(handle => {
            handle.addEventListener('mousedown', (event) => this.startDrag(event, handle))
          })

          this._onMouseMove = (event) => this.handleDrag(event)
          this._onMouseUp = (event) => this.endDrag(event)
          document.addEventListener('mousemove', this._onMouseMove)
          document.addEventListener('mouseup', this._onMouseUp)
        },

        bindToggleButtons() {
          const toggles = this.el.querySelectorAll('.panel-toggle')
          toggles.forEach(btn => {
            btn.addEventListener('click', () => {
              const panel = btn.dataset.panel
              this.togglePanel(panel)
            })
          })
        },

        bindRailClickHandlers() {
          if (!this.contextPanel) return

          const railSelectors = [
            '.rail-alarm-badge',
            '.rail-command-badge',
            '.rail-queue-badge'
          ]

          railSelectors.forEach(selector => {
            const elements = this.contextPanel.querySelectorAll(selector)
            elements.forEach(el => {
              el.addEventListener('click', () => {
                if (!this.panelStates.context.open) {
                  this.openPanel('context')
                }
              })
            })
          })
        },

        applyPanelStates() {
          if (this.navPanel) {
            const navState = this.panelStates.navigation
            this.navPanel.style.width = `${navState.width}px`
            this.navPanel.classList.toggle('collapsed', !navState.open)
            this.updateToggleIcon('navigation', navState.open)
          }

          if (this.contextPanel) {
            const ctxState = this.panelStates.context
            this.contextPanel.style.width = `${ctxState.width}px`
            this.contextPanel.classList.toggle('collapsed', !ctxState.open)
            this.updateToggleIcon('context', ctxState.open)
          }
        },

        startDrag(event, handle) {
          event.preventDefault()
          this.isDragging = true
          this.dragPanel = handle.dataset.panel
          this.dragStartX = event.clientX
          this.dragStartWidth =
            this.panelStates[this.dragPanel].width ||
            (this.dragPanel === 'navigation'
              ? this.config.navigation.openWidth
              : this.config.context.openWidth)

          document.body.style.cursor = 'col-resize'
          document.body.style.userSelect = 'none'
          this.el.classList.add('is-dragging')
        },

        handleDrag(event) {
          if (!this.isDragging || !this.dragPanel) return

          const config = this.config[this.dragPanel]
          const deltaX = event.clientX - this.dragStartX
          let newWidth
          if (config.side === 'left') {
            newWidth = this.dragStartWidth + deltaX
          } else {
            newWidth = this.dragStartWidth - deltaX
          }

          newWidth = Math.max(config.minDragWidth, Math.min(config.maxDragWidth, newWidth))
          this.setPanelWidth(this.dragPanel, newWidth)

          const panelEl = this.dragPanel === 'navigation' ? this.navPanel : this.contextPanel
          if (panelEl) {
            panelEl.classList.toggle('in-snap-zone', newWidth < config.snapThreshold)
          }
        },

        endDrag() {
          if (!this.isDragging || !this.dragPanel) return

          const config = this.config[this.dragPanel]
          const currentWidth = this.panelStates[this.dragPanel].width

          if (currentWidth < config.snapThreshold) {
            this.closePanel(this.dragPanel)
          } else {
            const distToOpen = Math.abs(currentWidth - config.openWidth)
            if (distToOpen < 30) {
              this.setPanelWidth(this.dragPanel, config.openWidth)
            }
            this.panelStates[this.dragPanel].open = true
          }

          this.isDragging = false
          this.dragPanel = null
          document.body.style.cursor = ''
          document.body.style.userSelect = ''
          this.el.classList.remove('is-dragging')

          if (this.navPanel) this.navPanel.classList.remove('in-snap-zone')
          if (this.contextPanel) this.contextPanel.classList.remove('in-snap-zone')
          this.saveState()
        },

        setPanelWidth(panelName, width) {
          const panelEl = panelName === 'navigation' ? this.navPanel : this.contextPanel
          if (!panelEl) return

          panelEl.style.width = `${width}px`
          this.panelStates[panelName].width = width

          const config = this.config[panelName]
          const isCollapsed = width <= config.closedWidth + 10
          panelEl.classList.toggle('collapsed', isCollapsed)
        },

        togglePanel(panelName) {
          const state = this.panelStates[panelName]
          if (state.open) {
            this.closePanel(panelName)
          } else {
            this.openPanel(panelName)
          }
        },

        openPanel(panelName) {
          const config = this.config[panelName]
          const panelEl = panelName === 'navigation' ? this.navPanel : this.contextPanel
          if (!panelEl) return

          this.setPanelWidth(panelName, config.openWidth)
          panelEl.classList.remove('collapsed')
          this.panelStates[panelName].open = true
          this.updateToggleIcon(panelName, true)
          this.saveState()
        },

        closePanel(panelName) {
          const config = this.config[panelName]
          const panelEl = panelName === 'navigation' ? this.navPanel : this.contextPanel
          if (!panelEl) return

          this.setPanelWidth(panelName, config.closedWidth)
          panelEl.classList.add('collapsed')
          this.panelStates[panelName].open = false
          this.updateToggleIcon(panelName, false)
          this.saveState()
        },

        updateToggleIcon(panelName, isOpen) {
          const btn = this.el.querySelector(`.panel-toggle[data-panel="${panelName}"]`)
          if (!btn) return

          const icon = btn.querySelector('.toggle-icon')
          if (icon) {
            icon.style.transform = isOpen ? '' : 'rotate(180deg)'
          }
        },

        destroyed() {
          document.removeEventListener('mousemove', this._onMouseMove)
          document.removeEventListener('mouseup', this._onMouseUp)
        }
      }
    </script>
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
  attr :notifications, :list, default: []
  attr :notification_unread_count, :integer, default: 0
  attr :review_pending_count, :integer, default: 0
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
            <div class="flex items-center gap-2">
              <CadenceWeb.NotificationComponents.notification_bell
                id="mission-notification-bell-mobile"
                unread_count={@notification_unread_count}
                notifications={@notifications}
              />
              <.user_org_menu id="user-org-menu-mobile" current_scope={@current_scope} />
            </div>
          </div>
          
    <!-- Desktop: Fixed top bar (outside main, doesn't scroll) -->
          <div class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0">
            <CadenceWeb.NotificationComponents.notification_bell
              id="mission-notification-bell-desktop"
              unread_count={@notification_unread_count}
              notifications={@notifications}
            />
            <.user_org_menu id="user-org-menu-desktop" current_scope={@current_scope} size="sm" />
          </div>
          
    <!-- Main content area -->
          <main class="flex-1 overflow-y-auto bg-base-100">
            {@inner_content}
          </main>
        </div>
      </div>
      
    <!-- Sidebar - HUD Mission Control Style -->
      <div class="drawer-side">
        <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div
          data-sidebar-collapsible
          class="sidebar-collapsible sidebar-expanded min-h-full bg-base-200 dark:sidebar-dark-bg flex flex-col border-r border-primary/20 hud-grid relative"
        >
          <!-- Logo/Brand (h-10 matches top bar height) -->
          <div class="px-3 h-10 flex items-center border-b border-primary/20">
            <.link navigate={~p"/"} class="flex items-center gap-2">
              <div class="relative flex-shrink-0">
                <img src={~p"/images/logo.svg"} width="20" class="relative z-10" />
                <div class="absolute inset-0 blur-md bg-primary/30"></div>
              </div>
              <span class="text-xs font-bold tracking-[0.15em] text-primary sidebar-label">
                CADENCE
              </span>
            </.link>
          </div>
          
    <!-- Back to missions link -->
          <div class="py-2 border-b border-primary/20 sidebar-back-link">
            <.link
              navigate={~p"/missions"}
              class="flex items-center gap-2 text-xs text-base-content/50 hover:text-primary transition-colors uppercase tracking-wide"
            >
              <.icon name="hero-arrow-left" class="h-3 w-3 flex-shrink-0" />
              <span class="sidebar-label">All Missions</span>
            </.link>
          </div>
          
    <!-- Mission Header -->
          <%= if @mission do %>
            <div class="px-3 py-2 border-b border-primary/20 sidebar-expanded-only">
              <div class="flex flex-col gap-1">
                <span class="hud-label text-base-content/40">Mission</span>
                <h2 class="font-medium text-sm truncate">{@mission.name}</h2>
                <.status_badge status={@mission.status} />
              </div>
            </div>
          <% end %>
          
    <!-- Mission Navigation -->
          <nav class="flex-1 overflow-y-auto py-2">
            <ul class="menu menu-sm space-y-0.5">
              <.mission_navigation mission={@mission} current_path={@current_path} />
            </ul>
          </nav>
          
    <!-- Toggle Button -->
          <button
            type="button"
            class="sidebar-toggle-btn hidden lg:flex"
            phx-click={JS.dispatch("phx:toggle-sidebar")}
            title="Toggle sidebar"
          >
            <.icon name="hero-chevron-left" class="h-3 w-3 toggle-chevron transition-transform" />
          </button>
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
        :is_procedure_reviews,
        assigns.current_path == "#{base_path}/procedures/reviews" or
          String.starts_with?(assigns.current_path, "#{base_path}/procedures/reviews?")
      )
      |> assign(
        :is_automations,
        String.contains?(assigns.current_path, "#{base_path}/automations")
      )
      |> assign(:is_schedules, String.contains?(assigns.current_path, "#{base_path}/schedules"))
      |> assign(:is_settings, String.contains?(assigns.current_path, "#{base_path}/settings"))
      |> assign(:is_settings_general, assigns.current_path == "#{base_path}/settings")
      |> assign(
        :is_settings_procedures,
        assigns.current_path == "#{base_path}/settings/procedures"
      )
      |> assign(:is_transports, String.contains?(assigns.current_path, "#{base_path}/transports"))
      |> assign(:is_links, String.contains?(assigns.current_path, "#{base_path}/links"))

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
        label="Config"
        icon="hero-cog-8-tooth"
        expanded={@is_transports or @is_links}
      >
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/transports"} active={@is_transports}>
          Transports
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/links"} active={@is_links}>
          Links
        </.sidebar_nav_child>
      </.sidebar_nav_group>

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
        expanded={@is_procedures or @is_procedure_reviews or @is_automations or @is_schedules}
      >
        <.sidebar_nav_child
          navigate={~p"/missions/#{@mission}/procedures"}
          active={@is_procedures and not @is_procedure_reviews}
        >
          Procedures
        </.sidebar_nav_child>
        <.sidebar_nav_child
          navigate={~p"/missions/#{@mission}/procedures/reviews"}
          active={@is_procedure_reviews}
        >
          Reviews
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/automations"} active={@is_automations}>
          Automations
        </.sidebar_nav_child>
        <.sidebar_nav_child navigate={~p"/missions/#{@mission}/schedules"} active={@is_schedules}>
          Schedules
        </.sidebar_nav_child>
      </.sidebar_nav_group>

      <.sidebar_nav_group
        label="Settings"
        icon="hero-cog-6-tooth"
        expanded={@is_settings}
      >
        <.sidebar_nav_child
          navigate={~p"/missions/#{@mission}/settings"}
          active={@is_settings_general}
        >
          General
        </.sidebar_nav_child>
        <.sidebar_nav_child
          navigate={~p"/missions/#{@mission}/settings/procedures"}
          active={@is_settings_procedures}
        >
          Procedures
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

  @doc """
  Renders a sidebar layout for user profile settings.

  This layout is used for profile-related pages like account settings,
  email management, and notification preferences.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :inner_content, :any, required: true

  def profile_sidebar(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="profile-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col">
        <!-- Page content -->
        <div class="flex flex-col h-screen">
          <!-- Top bar (mobile) -->
          <div class="lg:hidden flex items-center justify-between p-4 border-b border-base-300">
            <label for="profile-drawer" class="btn btn-ghost drawer-button">
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </label>
            <div class="flex-1 text-center font-semibold text-lg">Profile Settings</div>
            <div class="w-10"></div>
          </div>
          
    <!-- Main content area -->
          <main class="flex-1 overflow-y-auto bg-base-100">
            <!-- Desktop: Back link in top-right -->
            <div class="hidden lg:flex items-center justify-end p-4 border-b border-base-300">
              <.link navigate={~p"/missions"} class="btn btn-ghost btn-sm gap-2">
                <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to Cadence
              </.link>
            </div>
            
    <!-- Page content -->
            <div class="p-6">
              {@inner_content}
            </div>
          </main>
        </div>
      </div>
      
    <!-- Sidebar - HUD Mission Control Style -->
      <div class="drawer-side">
        <label for="profile-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <div
          data-sidebar-collapsible
          class="sidebar-collapsible sidebar-expanded min-h-full bg-base-200 dark:sidebar-dark-bg flex flex-col border-r border-primary/20 hud-grid relative"
        >
          <!-- Back link -->
          <div class="px-3 py-2 border-b border-primary/20">
            <.link
              navigate={~p"/missions"}
              class="flex items-center gap-2 text-xs text-base-content/50 hover:text-primary transition-colors uppercase tracking-wide"
            >
              <.icon name="hero-arrow-left" class="h-3 w-3 flex-shrink-0" />
              <span class="sidebar-label">Back to Cadence</span>
            </.link>
          </div>
          
    <!-- User header -->
          <div class="p-3 border-b border-primary/20 sidebar-expanded-only">
            <div class="flex items-center gap-2">
              <.avatar email={@current_scope.user.email} size="sm" />
              <div class="flex-1 min-w-0">
                <p class="font-medium text-sm truncate">{@current_scope.user.email}</p>
                <p class="text-[0.65rem] text-base-content/40 uppercase tracking-wide">Profile</p>
              </div>
            </div>
          </div>
          
    <!-- Collapsed avatar - visible only when collapsed -->
          <div class="p-2 border-b border-primary/20 sidebar-collapsed-only flex justify-center">
            <.avatar email={@current_scope.user.email} size="sm" />
          </div>
          
    <!-- Navigation -->
          <nav class="flex-1 overflow-y-auto py-2">
            <ul class="menu menu-sm space-y-0.5">
              <.profile_navigation current_path={@current_path} />
            </ul>
          </nav>
          
    <!-- Toggle Button -->
          <button
            type="button"
            class="sidebar-toggle-btn hidden lg:flex"
            phx-click={JS.dispatch("phx:toggle-sidebar")}
            title="Toggle sidebar"
          >
            <.icon name="hero-chevron-left" class="h-3 w-3 toggle-chevron transition-transform" />
          </button>
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders navigation items for profile settings.
  """
  attr :current_path, :string, default: ""

  def profile_navigation(assigns) do
    assigns =
      assigns
      |> assign(:is_profile, assigns.current_path == "/profile")
      |> assign(:is_email, assigns.current_path == "/profile/email")
      |> assign(:is_appearance, assigns.current_path == "/profile/appearance")
      |> assign(:is_notifications, assigns.current_path == "/profile/notifications")

    ~H"""
    <.sidebar_nav_item navigate={~p"/profile"} active={@is_profile}>
      <:icon><.icon name="hero-user" class="h-5 w-5" /></:icon>
      Profile
    </.sidebar_nav_item>

    <.sidebar_nav_item navigate={~p"/profile/email"} active={@is_email}>
      <:icon><.icon name="hero-envelope" class="h-5 w-5" /></:icon>
      Email
    </.sidebar_nav_item>

    <.sidebar_nav_item navigate={~p"/profile/appearance"} active={@is_appearance}>
      <:icon><.icon name="hero-paint-brush" class="h-5 w-5" /></:icon>
      Appearance
    </.sidebar_nav_item>

    <.sidebar_nav_item navigate={~p"/profile/notifications"} active={@is_notifications}>
      <:icon><.icon name="hero-bell" class="h-5 w-5" /></:icon>
      Notifications
    </.sidebar_nav_item>
    """
  end

  # Helper for chevron icon size in user menu
  defp chevron_class("sm"), do: "hidden sm:block h-3 w-3"
  defp chevron_class("md"), do: "hidden sm:block h-4 w-4"
  defp chevron_class(_), do: "hidden sm:block h-4 w-4"
end
