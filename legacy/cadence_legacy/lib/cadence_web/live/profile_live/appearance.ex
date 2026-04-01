defmodule CadenceWeb.ProfileLive.Appearance do
  @moduledoc """
  LiveView for user appearance settings.

  Allows users to select their preferred theme (system, light, or dark).
  """
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Appearance")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <.header>
        Appearance
        <:subtitle>Customize the look and feel of Cadence</:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <h3 class="card-title text-base">Theme</h3>
            <p class="text-sm text-base-content/60 mt-1">
              Choose your preferred color scheme. System will automatically match your device settings.
            </p>

            <div class="mt-6 flex flex-col sm:flex-row gap-4">
              <.theme_option
                theme="system"
                label="System"
                description="Follow device settings"
                icon="hero-computer-desktop"
              />
              <.theme_option
                theme="light"
                label="Light"
                description="Always use light mode"
                icon="hero-sun"
              />
              <.theme_option
                theme="dark"
                label="Dark"
                description="Always use dark mode"
                icon="hero-moon"
              />
            </div>
          </div>
        </div>

        <div class="card bg-base-200/50 border border-base-300">
          <div class="card-body">
            <h4 class="font-medium">About Themes</h4>
            <p class="mt-2 text-sm text-base-content/70">
              Your theme preference is saved locally in your browser and will persist across sessions.
              Choosing "System" will automatically switch between light and dark mode based on your
              operating system preferences.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :theme, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true

  defp theme_option(assigns) do
    ~H"""
    <button
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme={@theme}
      class={[
        "flex-1 p-4 rounded-lg border-2 cursor-pointer transition-all",
        "hover:border-primary/50 hover:bg-base-200/50",
        "focus:outline-none focus:ring-2 focus:ring-primary/50",
        theme_active_class(@theme)
      ]}
    >
      <div class="flex flex-col items-center gap-2">
        <.icon name={@icon} class="h-8 w-8" />
        <span class="font-medium">{@label}</span>
        <span class="text-xs text-base-content/60 text-center">{@description}</span>
      </div>
    </button>
    """
  end

  defp theme_active_class("system") do
    "border-base-300 [[data-theme=light]_&]:border-base-300 [[data-theme=dark]_&]:border-base-300 [:not([data-theme])_&]:border-primary"
  end

  defp theme_active_class("light") do
    "border-base-300 [[data-theme=light]_&]:border-primary"
  end

  defp theme_active_class("dark") do
    "border-base-300 [[data-theme=dark]_&]:border-primary"
  end
end
