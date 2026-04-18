defmodule CadenceWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  attr :field, FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :options, :list, default: []
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete autofocus disabled maxlength minlength pattern)

  def input(assigns) do
    value =
      case assigns.type do
        "password" -> nil
        _other -> assigns.field.value
      end

    errors =
      if Phoenix.Component.used_input?(assigns.field),
        do: assigns.field.errors,
        else: []

    assigns = assigns |> assign(:value, value) |> assign(:errors, errors)

    ~H"""
    <div class="fieldset mb-3">
      <label>
        <span :if={@label} class="hud-label block mb-1.5">{@label}</span>
        <%= if @type == "select" do %>
          <select
            id={@field.id}
            name={@field.name}
            required={@required}
            class={["w-full select", @errors != [] && "select-error", @class]}
            {@rest}
          >
            <option :if={@placeholder} value="">{@placeholder}</option>
            <option
              :for={{label, option_value} <- @options}
              value={option_value}
              selected={to_string(@value) == to_string(option_value)}
            >
              {label}
            </option>
          </select>
        <% else %>
          <input
            id={@field.id}
            name={@field.name}
            type={@type}
            value={@value}
            placeholder={@placeholder}
            required={@required}
            class={["w-full input", @errors != [] && "input-error", @class]}
            {@rest}
          />
        <% end %>
      </label>
      <p :for={{msg, _opts} <- @errors} class="mt-1.5 text-sm text-error">
        {msg}
      </p>
    </div>
    """
  end

  @doc """
  Renders a vertical ellipsis action menu for table rows and card actions.

  Uses daisyUI's dropdown pattern with the HUD-styled dropdown-content
  (sharp corners, cyan border, backdrop blur — from component-overrides.css).
  Each action is a slot that receives the row item and renders as a menu item.

  ## Examples

      <.action_menu>
        <:action>
          <.link navigate={~p"/things/\#{thing.id}"}>View</.link>
        </:action>
        <:action>
          <button phx-click="delete" phx-value-id={thing.id}
            data-confirm="Are you sure?">Delete</button>
        </:action>
      </.action_menu>
  """
  attr :class, :string, default: nil
  slot :action, required: true

  def action_menu(assigns) do
    ~H"""
    <div class={["dropdown dropdown-end", @class]}>
      <div tabindex="0" role="button" class="btn btn-ghost btn-xs">
        <span class="hero-ellipsis-vertical h-5 w-5"></span>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-200 z-[100] w-52 p-2 shadow-lg border border-primary/20"
      >
        <li :for={action <- @action}>{render_slot(action)}</li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders a colored status indicator dot.

  ## Examples

      <.status_dot status={:online} />
      <.status_dot status={:fault} size={:sm} />
  """
  attr :status, :atom,
    required: true,
    values: [:online, :offline, :standby, :fault, :critical, :warning, :info, :success, :nominal]

  attr :size, :atom, values: [:sm, :md], default: :md
  attr :class, :string, default: nil

  def status_dot(assigns) do
    ~H"""
    <span class={[
      "rounded-full flex-shrink-0",
      size_class(@size),
      status_color(@status),
      @class
    ]}>
    </span>
    """
  end

  defp size_class(:sm), do: "w-1.5 h-1.5"
  defp size_class(:md), do: "w-2 h-2"

  defp status_color(:online), do: "bg-success"
  defp status_color(:nominal), do: "bg-success"
  defp status_color(:success), do: "bg-success"
  defp status_color(:standby), do: "bg-warning"
  defp status_color(:warning), do: "bg-warning"
  defp status_color(:fault), do: "bg-error"
  defp status_color(:critical), do: "bg-error"
  defp status_color(:info), do: "bg-info"
  defp status_color(:offline), do: "bg-base-content/30"

  @doc """
  Renders a key-value detail row. Wrap multiple rows in a `divide-y divide-base-300`
  container for dividers between them.

  ## Examples

      <div class="divide-y divide-base-300">
        <.detail_row label="Slug" value={@org.slug} mono />
        <.detail_row label="Status" value="Active" />
      </div>
  """
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :mono, :boolean, default: false
  slot :inner_block

  def detail_row(assigns) do
    ~H"""
    <div class="py-3 flex justify-between">
      <span class="text-base-content/60">{@label}</span>
      <span class={[@mono && "font-mono text-sm"]}>
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@value || "—"}
        <% end %>
      </span>
    </div>
    """
  end

  @doc """
  Renders an empty state placeholder for lists and tables with no data.

  ## Examples

      <.empty_state
        icon="hero-building-office"
        title="No organizations"
        description="Create your first organization to get started."
        action_label="Create Organization"
        action_navigate={~p"/admin/organizations/new"}
      />
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :action_label, :string, default: nil
  attr :action_navigate, :string, default: nil
  attr :action_patch, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-12 border border-dashed border-base-300 rounded-sm bg-base-200/30">
      <span class={[@icon, "mx-auto h-12 w-12 text-base-content/30"]}></span>
      <h3 class="mt-2 text-sm font-semibold text-base-content">{@title}</h3>
      <p :if={@description} class="mt-1 text-sm text-base-content/60">{@description}</p>
      <div :if={@action_label} class="mt-6">
        <.link
          navigate={@action_navigate}
          patch={@action_patch}
          class="btn btn-primary btn-sm"
        >
          <span class="hero-plus -ml-0.5 mr-1.5 h-5 w-5"></span>
          {@action_label}
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders an inline severity badge with a status dot, optional count, and label.

  ## Examples

      <.severity_badge severity={:critical} count={3} />
      <.severity_badge severity={:warning} count={12} />
      <.severity_badge severity={:info} />
  """
  attr :severity, :atom, required: true, values: [:critical, :warning, :info, :nominal]
  attr :count, :integer, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: nil

  def severity_badge(assigns) do
    assigns =
      assign_new(assigns, :resolved_label, fn ->
        assigns.label || severity_label(assigns.severity)
      end)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs font-medium",
      severity_badge_class(@severity),
      @class
    ]}>
      <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
      <span :if={@count} class="font-mono">{@count}</span>
      <span class="uppercase text-[0.65rem]">{@resolved_label}</span>
    </span>
    """
  end

  defp severity_badge_class(:critical), do: "bg-error/20 text-error"
  defp severity_badge_class(:warning), do: "bg-warning/20 text-warning"
  defp severity_badge_class(:info), do: "bg-info/20 text-info"
  defp severity_badge_class(:nominal), do: "bg-success/20 text-success"

  defp severity_label(:critical), do: "CRIT"
  defp severity_label(:warning), do: "WARN"
  defp severity_label(:info), do: "INFO"
  defp severity_label(:nominal), do: "NOM"

  @doc """
  Renders a panel/section header bar with an uppercase label and optional right-side controls.

  ## Examples

      <.panel_header label="Active Alarms" count={5}>
        <:controls>
          <button class="btn btn-ghost btn-xs">Filter</button>
        </:controls>
      </.panel_header>
  """
  attr :label, :string, required: true
  attr :count, :integer, default: nil
  attr :class, :string, default: nil
  slot :controls

  def panel_header(assigns) do
    ~H"""
    <div class={["flex items-center justify-between px-2 py-1.5 border-b border-base-300", @class]}>
      <div class="flex items-center gap-2">
        <span class="hud-label text-base-content/40">{@label}</span>
        <span :if={@count} class="text-xs text-base-content/60">({@count})</span>
      </div>
      <div :if={@controls != []} class="flex items-center gap-1">
        {render_slot(@controls)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a list item row with a status dot, name, detail text, and optional right-side info.

  ## Examples

      <.list_item
        name={target.name}
        detail={target.identifier}
        status={:online}
        badge={target.type}
      />
  """
  attr :name, :string, required: true
  attr :detail, :string, default: nil
  attr :status, :atom, default: nil
  attr :badge, :string, default: nil
  attr :class, :string, default: nil

  def list_item(assigns) do
    ~H"""
    <div class={["flex items-center justify-between py-2", @class]}>
      <div class="flex items-center gap-3">
        <.status_dot :if={@status} status={@status} />
        <div>
          <p class="font-medium text-sm">{@name}</p>
          <p :if={@detail} class="text-xs text-base-content/50">{@detail}</p>
        </div>
      </div>
      <span :if={@badge} class="text-xs text-base-content/50">{@badge}</span>
    </div>
    """
  end

  @doc """
  Renders a resizable two-panel split layout with a drag handle between them.

  Uses the `ResizablePanel` LiveView JS hook for drag-to-resize with localStorage
  persistence. The left panel width is controlled; the right panel fills remaining space.

  ## Examples

      <.resizable_split id="cmd-panels" default_width="40%">
        <:left>
          <.panel_header label="Targets" />
          <!-- target list -->
        </:left>
        <:right>
          <.panel_header label="Commands" />
          <!-- command browser -->
        </:right>
      </.resizable_split>
  """
  attr :id, :string, required: true
  attr :default_width, :string, default: "40%"
  attr :min_width, :integer, default: 150
  attr :max_width_percent, :integer, default: 60
  attr :class, :string, default: nil
  slot :left, required: true
  slot :right, required: true

  def resizable_split(assigns) do
    ~H"""
    <div id={@id} class={["flex h-full overflow-hidden", @class]}>
      <div
        id={"#{@id}-left"}
        class="flex flex-col overflow-hidden flex-shrink-0"
        style={"flex: 0 0 #{@default_width}"}
      >
        {render_slot(@left)}
      </div>
      <div
        id={"#{@id}-handle"}
        phx-hook="ResizablePanel"
        phx-update="ignore"
        data-panel-id={"#{@id}-left"}
        data-storage-key={"cadence:panel:#{@id}"}
        data-min-width={@min_width}
        data-max-width-pct={@max_width_percent}
        class="w-2 flex-shrink-0 cursor-col-resize flex items-center justify-center relative z-10 group"
      >
        <div class="w-0.5 h-10 rounded-full transition-all bg-base-content/20 group-hover:bg-primary/60 group-hover:h-16 group-hover:shadow-[0_0_8px_rgba(125,207,255,0.3)]">
        </div>
      </div>
      <div class="flex-1 flex flex-col overflow-hidden">
        {render_slot(@right)}
      </div>
    </div>
    """
  end
end
