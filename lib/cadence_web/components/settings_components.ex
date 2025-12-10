defmodule CadenceWeb.SettingsComponents do
  @moduledoc """
  Provides UI components for settings pages.

  These components are used to build consistent settings interfaces
  across organization and mission settings pages.
  """
  use Phoenix.Component

  import CadenceWeb.CoreComponents

  @doc """
  Renders a settings page layout with tabs and content area.

  ## Examples

      <.settings_layout>
        <:tabs>
          <.settings_tab navigate={~p"/settings"} active={true}>General</.settings_tab>
        </:tabs>
        <:content>
          Settings content here
        </:content>
      </.settings_layout>
  """
  slot :tabs, required: true
  slot :content, required: true

  def settings_layout(assigns) do
    ~H"""
    <div class="flex flex-col lg:flex-row gap-6">
      <!-- Tabs sidebar -->
      <div class="lg:w-64 shrink-0">
        <nav class="flex lg:flex-col gap-1 overflow-x-auto lg:overflow-x-visible">
          {render_slot(@tabs)}
        </nav>
      </div>
      <!-- Content area -->
      <div class="flex-1 min-w-0">
        {render_slot(@content)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a settings tab navigation item.

  ## Examples

      <.settings_tab navigate={~p"/settings"} active={true} icon="hero-building-office">
        General
      </.settings_tab>
  """
  attr :navigate, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  def settings_tab(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-3 px-4 py-3 rounded-lg whitespace-nowrap transition-all",
        @active && "bg-primary/10 text-primary font-semibold",
        !@active && "text-base-content/70 hover:bg-base-200"
      ]}
    >
      <.icon :if={@icon} name={@icon} class="h-5 w-5" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a settings section with title and optional description.

  ## Examples

      <.settings_section title="Approval Workflow" description="Configure how procedures are reviewed">
        Section content here
      </.settings_section>
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
  Renders a setting card with label, description, and control slot.

  ## Examples

      <.setting_card label="Required Approvals" description="Number of approvals needed">
        <.setting_number_input value={2} min={1} max={10} name="required_approvals" />
      </.setting_card>
  """
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  def setting_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300">
      <div class="card-body p-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex-1">
            <h3 class="font-medium">{@label}</h3>
            <p :if={@description} class="text-sm text-base-content/60 mt-1">{@description}</p>
            <p :if={@hint} class="text-xs text-base-content/50 mt-2 italic">{@hint}</p>
          </div>
          <div class="shrink-0">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a number input for settings.

  ## Examples

      <.setting_number_input value={2} min={1} max={10} name="required_approvals" phx-change="save_setting" />
  """
  attr :value, :any, required: true
  attr :min, :integer, default: nil
  attr :max, :integer, default: nil
  attr :name, :string, required: true
  attr :rest, :global, include: ~w(phx-change phx-blur disabled)

  def setting_number_input(assigns) do
    ~H"""
    <input
      type="number"
      name={"value"}
      value={@value}
      min={@min}
      max={@max}
      phx-value-key={@name}
      class="input input-bordered input-sm w-24 text-center"
      {@rest}
    />
    """
  end

  @doc """
  Renders a toggle switch for boolean settings.

  ## Examples

      <.setting_toggle value={true} name="allow_self_approval" phx-change="save_setting" />
  """
  attr :value, :boolean, required: true
  attr :name, :string, required: true
  attr :rest, :global, include: ~w(phx-change phx-blur disabled)

  def setting_toggle(assigns) do
    ~H"""
    <input type="hidden" name="value" value="false" />
    <input
      type="checkbox"
      name={"value"}
      value="true"
      checked={@value}
      phx-value-key={@name}
      class="toggle toggle-primary"
      {@rest}
    />
    """
  end
end
