defmodule CadenceWeb.SettingsComponents do
  @moduledoc """
  UI components for settings pages.

  Provides layout components (settings_section) for organizing settings pages,
  plus card components (setting_card, setting_toggle, setting_number_input,
  setting_override_card) for displaying and editing settings.

  These components support hierarchical settings with organization defaults
  and mission-level overrides, including restrictiveness hints.
  """

  use Phoenix.Component

  import CadenceWeb.CoreComponents, only: [icon: 1]

  ## Layout Components

  @doc """
  Renders a settings section with a header and grouped content.

  Use this to group related settings together with a descriptive title
  and optional description.

  ## Examples

      <.settings_section title="Approval Workflow" description="Configure how procedures are approved">
        <!-- Settings cards here -->
      </.settings_section>

      <.settings_section title="General Settings">
        <!-- Settings cards here -->
      </.settings_section>
  """
  attr :title, :string, required: true, doc: "Section title"
  attr :description, :string, default: nil, doc: "Optional section description"

  slot :inner_block, required: true, doc: "Settings cards or content"

  def settings_section(assigns) do
    ~H"""
    <section class="mb-8">
      <header class="mb-4">
        <h2 class="text-lg font-semibold mb-1">{@title}</h2>
        <p :if={@description} class="text-sm text-base-content/60">{@description}</p>
      </header>
      <div class="space-y-4">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  ## Restrictiveness Hint Text Helpers

  @doc """
  Returns a human-readable hint based on the restrictiveness rule.
  """
  def restrictiveness_hint(:higher), do: "Missions can require more, but not fewer"
  def restrictiveness_hint(:lower), do: "Missions can set lower, but not higher"

  def restrictiveness_hint(:false_is_stricter),
    do: "Missions can disable, but cannot re-enable if disabled at org level"

  def restrictiveness_hint(:none), do: "Missions can set any valid value"
  def restrictiveness_hint(_), do: nil

  ## Card Components

  @doc """
  Renders a base card wrapper for any setting.

  Provides consistent layout with label, description, hint, and error display.

  ## Examples

      <.setting_card label="Required Approvals" description="Number of approvals needed...">
        <input type="number" value="1" />
      </.setting_card>

      <.setting_card
        label="Required Approvals"
        description="Number of approvals needed..."
        hint="Missions can require more, but not fewer"
        error="Value must be between 1 and 10"
      >
        <input type="number" value="0" />
      </.setting_card>
  """
  attr :label, :string, required: true, doc: "Setting label"
  attr :description, :string, required: true, doc: "Setting description"
  attr :hint, :string, default: nil, doc: "Optional hint text (for restrictiveness info)"
  attr :error, :string, default: nil, doc: "Optional error message"

  slot :inner_block, required: true, doc: "The input control"

  def setting_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 p-4">
      <div class="text-base font-semibold">{@label}</div>
      <p class="text-sm text-base-content/60 mt-1 mb-4">{@description}</p>

      <div>
        {render_slot(@inner_block)}
      </div>

      <div :if={@hint} class="text-xs text-info mt-2 flex items-center gap-1">
        <.icon name="hero-information-circle" class="size-4" />
        <span>{@hint}</span>
      </div>

      <div :if={@error} class="text-xs text-error mt-2 flex items-center gap-1">
        <.icon name="hero-exclamation-circle" class="size-4" />
        <span>{@error}</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders an integer input with increment/decrement buttons.

  Used for settings like `required_approvals`.

  ## Examples

      <.setting_number_input
        value={1}
        min={1}
        max={10}
        name="required_approvals"
        phx-change="save_setting"
      />
  """
  attr :value, :integer, required: true, doc: "Current integer value"
  attr :min, :integer, default: nil, doc: "Minimum allowed value"
  attr :max, :integer, default: nil, doc: "Maximum allowed value"
  attr :name, :string, required: true, doc: "Form field name"
  attr :disabled, :boolean, default: false, doc: "Whether the input is disabled"
  attr :rest, :global, include: ~w(phx-change phx-target phx-debounce)

  def setting_number_input(assigns) do
    ~H"""
    <div class="join">
      <button
        type="button"
        class="btn btn-sm btn-ghost join-item"
        phx-click="decrement_setting"
        phx-value-name={@name}
        disabled={@disabled || (@min != nil && @value <= @min)}
      >
        <.icon name="hero-minus" class="size-4" />
      </button>
      <input
        type="number"
        name={@name}
        value={@value}
        min={@min}
        max={@max}
        disabled={@disabled}
        class={[
          "input input-sm input-bordered join-item w-16 text-center",
          @disabled && "input-disabled"
        ]}
        {@rest}
      />
      <button
        type="button"
        class="btn btn-sm btn-ghost join-item"
        phx-click="increment_setting"
        phx-value-name={@name}
        disabled={@disabled || (@max != nil && @value >= @max)}
      >
        <.icon name="hero-plus" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a boolean toggle switch.

  Used for settings like `allow_self_approval`.

  ## Examples

      <.setting_toggle
        value={true}
        name="allow_self_approval"
        phx-change="save_setting"
      />

      <.setting_toggle
        value={false}
        name="allow_self_approval"
        enabled_label="Allowed"
        disabled_label="Not Allowed"
        phx-change="save_setting"
      />
  """
  attr :value, :boolean, required: true, doc: "Current boolean value"
  attr :name, :string, required: true, doc: "Form field name"
  attr :disabled, :boolean, default: false, doc: "Whether the toggle is disabled"
  attr :enabled_label, :string, default: "Enabled", doc: "Text when true"
  attr :disabled_label, :string, default: "Disabled", doc: "Text when false"
  attr :rest, :global, include: ~w(phx-change phx-target)

  def setting_toggle(assigns) do
    ~H"""
    <form phx-change={@rest[:"phx-change"]} phx-target={@rest[:"phx-target"]}>
      <label class="flex items-center gap-3 cursor-pointer">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          name={@name}
          value="true"
          checked={@value}
          disabled={@disabled}
          class={["toggle toggle-primary", @disabled && "toggle-disabled"]}
        />
        <span class="text-sm">
          {if @value, do: @enabled_label, else: @disabled_label}
        </span>
      </label>
    </form>
    """
  end

  @doc """
  Renders a mission-level setting card with org default context.

  Always shows the control, but constrains or locks it based on the
  organization's restrictiveness rules.

  ## Examples

      <.setting_override_card
        label="Required Approvals"
        description="Number of approvals needed..."
        type={:integer}
        org_value={1}
        effective_value={3}
        min_value={1}
        max_value={10}
        restrictiveness={:higher}
        name="required_approvals"
      />
  """
  attr :label, :string, required: true, doc: "Setting label from definition"
  attr :description, :string, required: true, doc: "Setting description from definition"
  attr :type, :atom, required: true, values: [:integer, :boolean], doc: "Setting value type"
  attr :org_value, :any, required: true, doc: "Organization default value"
  attr :effective_value, :any, required: true, doc: "Current effective value for this mission"
  attr :min_value, :integer, default: nil, doc: "Minimum allowed value (for integers)"
  attr :max_value, :integer, default: nil, doc: "Maximum allowed value (for integers)"
  attr :restrictiveness, :atom, default: :none, doc: "Restrictiveness rule for generating hint"
  attr :name, :any, required: true, doc: "Form field name (string or atom)"
  attr :error, :string, default: nil, doc: "Error message"
  attr :can_override, :boolean, default: true, doc: "Whether override is allowed"
  attr :rest, :global, include: ~w(phx-change phx-target)

  def setting_override_card(assigns) do
    # Determine if control is locked (for boolean with false_is_stricter when org is false)
    is_locked =
      not assigns.can_override or
        (assigns.type == :boolean and
           assigns.restrictiveness == :false_is_stricter and
           assigns.org_value == false)

    # Generate constraint hint based on restrictiveness
    constraint_hint = build_constraint_hint(assigns.restrictiveness, assigns.org_value)

    # Ensure name is a string for the form
    name_str = to_string(assigns.name)

    assigns =
      assigns
      |> assign(:is_locked, is_locked)
      |> assign(:constraint_hint, constraint_hint)
      |> assign(:name_str, name_str)

    ~H"""
    <div class="card bg-base-100 border border-base-300 p-4">
      <div class="text-base font-semibold">{@label}</div>
      <p class="text-sm text-base-content/60 mt-1 mb-4">{@description}</p>

      <div class="bg-base-200 rounded-lg px-3 py-2 mb-4 flex items-center gap-2">
        <span class="text-sm text-base-content/70">Organization default:</span>
        <span class="font-medium">{format_value(@org_value)}</span>
      </div>

      <div class="flex items-center gap-3">
        <%= if @type == :integer do %>
          <.setting_number_input
            value={@effective_value}
            min={@min_value}
            max={@max_value}
            name={@name_str}
            disabled={@is_locked}
            {@rest}
          />
        <% else %>
          <.setting_toggle
            value={@effective_value}
            name={@name_str}
            disabled={@is_locked}
            {@rest}
          />
        <% end %>
      </div>

      <div :if={@is_locked} class="text-xs text-warning mt-2 flex items-center gap-1">
        <.icon name="hero-lock-closed" class="size-4" />
        <span>Locked by organization policy</span>
      </div>

      <div
        :if={@constraint_hint && not @is_locked}
        class="text-xs text-info mt-2 flex items-center gap-1"
      >
        <.icon name="hero-information-circle" class="size-4" />
        <span>{@constraint_hint}</span>
      </div>

      <div :if={@error} class="text-xs text-error mt-2 flex items-center gap-1">
        <.icon name="hero-exclamation-circle" class="size-4" />
        <span>{@error}</span>
      </div>
    </div>
    """
  end

  ## Private Helpers

  defp format_value(true), do: "Enabled"
  defp format_value(false), do: "Disabled"
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value), do: to_string(value)

  defp build_constraint_hint(:higher, org_value) when is_integer(org_value) do
    "Must be at least #{org_value}"
  end

  defp build_constraint_hint(:lower, org_value) when is_integer(org_value) do
    "Must be at most #{org_value}"
  end

  defp build_constraint_hint(:false_is_stricter, true) do
    "Can disable, but cannot re-enable"
  end

  defp build_constraint_hint(:false_is_stricter, false) do
    "Cannot enable (disabled at organization level)"
  end

  defp build_constraint_hint(:none, _), do: nil
  defp build_constraint_hint(_, _), do: nil
end
