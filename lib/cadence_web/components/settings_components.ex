defmodule CadenceWeb.SettingsComponents do
  @moduledoc """
  UI components for settings pages.
  """
  use Phoenix.Component

  import CadenceWeb.CoreComponents

  @doc """
  Renders a settings layout with tabs and content.
  """
  slot :tabs, required: true
  slot :content, required: true

  def settings_layout(assigns) do
    ~H"""
    <div class="flex gap-8">
      <nav class="w-48 shrink-0">
        <ul class="space-y-1">
          {render_slot(@tabs)}
        </ul>
      </nav>
      <div class="flex-1 min-w-0">
        {render_slot(@content)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a settings navigation tab.
  """
  attr :navigate, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, required: true
  slot :inner_block, required: true

  def settings_tab(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@navigate}
        class={[
          "flex items-center gap-3 px-3 py-2 rounded-lg transition-all text-sm",
          @active && "bg-primary/10 text-primary font-medium",
          not @active && "text-base-content/70 hover:bg-base-200"
        ]}
      >
        <.icon name={@icon} class="h-4 w-4" />
        {render_slot(@inner_block)}
      </.link>
    </li>
    """
  end

  @doc """
  Renders a settings section with title and optional description.
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  def settings_section(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <h2 class="text-lg font-semibold">{@title}</h2>
        <p :if={@description} class="text-sm text-base-content/60 mt-1">{@description}</p>
      </div>
      <div class="space-y-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a setting override card for mission settings.

  This component displays the organization default value and allows
  mission-level overrides with validation.
  """
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :type, :atom, required: true
  attr :org_value, :any, required: true
  attr :mission_override, :any, default: nil
  attr :has_override, :boolean, default: false
  attr :min_value, :integer, default: nil
  attr :max_value, :integer, default: nil
  attr :restrictiveness, :atom, default: :none
  attr :name, :atom, required: true
  attr :error, :string, default: nil

  def setting_override_card(assigns) do
    # Determine if override toggle is disabled (for boolean with false_is_stricter when org is false)
    override_disabled =
      assigns.type == :boolean and
        assigns.restrictiveness == :false_is_stricter and
        assigns.org_value == false

    assigns = assign(assigns, :override_disabled, override_disabled)

    ~H"""
    <div class="card bg-base-100 border border-base-300">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1">
            <h3 class="font-medium">{@label}</h3>
            <p :if={@description} class="text-sm text-base-content/60 mt-1">{@description}</p>

            <div class="mt-2 text-sm">
              <span class="text-base-content/50">Organization default: </span>
              <span class="font-medium">{format_value(@org_value, @type)}</span>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <label class="label cursor-pointer gap-2">
              <span class="label-text text-sm">Override</span>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                checked={@has_override}
                disabled={@override_disabled}
                phx-click="toggle_override"
                phx-value-key={@name}
              />
            </label>
          </div>
        </div>

        <div :if={@override_disabled} class="mt-2 text-sm text-warning">
          Cannot override - disabled at organization level
        </div>

        <div :if={@has_override and not @override_disabled} class="mt-4 pt-4 border-t border-base-200">
          <div class="flex items-center gap-4">
            <div class="flex-1">
              <%= case @type do %>
                <% :integer -> %>
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      class={[
                        "input input-bordered input-sm w-24",
                        @error && "input-error"
                      ]}
                      value={@mission_override || @org_value}
                      min={@min_value}
                      max={@max_value}
                      phx-blur="save_setting"
                      phx-value-key={@name}
                    />
                    <span :if={@restrictiveness == :higher} class="text-xs text-base-content/50">
                      (min: {@org_value})
                    </span>
                    <span :if={@restrictiveness == :lower} class="text-xs text-base-content/50">
                      (max: {@org_value})
                    </span>
                  </div>
                <% :boolean -> %>
                  <label class="label cursor-pointer justify-start gap-3">
                    <input
                      type="checkbox"
                      class="toggle toggle-primary"
                      checked={@mission_override}
                      disabled={@restrictiveness == :false_is_stricter and @org_value == false}
                      phx-click="save_setting"
                      phx-value-key={@name}
                      phx-value-value={to_string(not @mission_override)}
                    />
                    <span class="label-text">
                      {if @mission_override, do: "Enabled", else: "Disabled"}
                    </span>
                  </label>
                <% :string -> %>
                  <input
                    type="text"
                    class={[
                      "input input-bordered input-sm w-full max-w-xs",
                      @error && "input-error"
                    ]}
                    value={@mission_override || @org_value}
                    phx-blur="save_setting"
                    phx-value-key={@name}
                  />
              <% end %>
            </div>
          </div>

          <p :if={@error} class="mt-2 text-sm text-error flex items-center gap-1">
            <.icon name="hero-exclamation-circle" class="h-4 w-4" />
            {@error}
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp format_value(value, :boolean), do: if(value, do: "Enabled", else: "Disabled")
  defp format_value(value, :integer), do: to_string(value)
  defp format_value(value, :string), do: value
  defp format_value(value, _), do: inspect(value)
end
