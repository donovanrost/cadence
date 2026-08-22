defmodule CadenceWeb.ApplicationInventoryCard do
  @moduledoc "Host-standard card for one application inventory item."

  use CadenceWeb, :html

  alias Cadence.Applications.HostContext

  attr :id, :string, required: true
  attr :app, :map, required: true
  attr :host_context, HostContext, required: true
  attr :manage_path, :string, required: true
  attr :scope_label, :string, default: "Application"

  def application_inventory_card(assigns) do
    ~H"""
    <.card id={@id}>
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label">{@scope_label}</p>
          <h2 class="mt-2 text-base font-semibold">{@app.display_name}</h2>
        </div>
        <.status_badge status={@app.status.tone} label={@app.status.label} />
      </div>
      <p class="mt-3 text-sm text-base-content/70">{@app.description}</p>
      <div class="mt-5 space-y-1">
        <.detail_row :for={fact <- @app.status.facts} label={fact.label} value={fact.value} />
      </div>
      <div class="mt-5 flex flex-wrap items-center gap-2">
        <.button :if={@app.manageable?} navigate={@manage_path}>
          Manage
        </.button>
        <.button
          :if={@app.installable? and not @app.manageable?}
          id={lifecycle_action_id("install", @host_context, @app.application_key)}
          type="button"
          phx-click="install_application"
          phx-value-key={@app.application_key}
        >
          {install_label(@app.lifecycle_state)}
        </.button>
        <.application_lifecycle_action
          :if={@app.manageable?}
          action_id="disable"
          id={lifecycle_action_id("disable", @host_context, @app.application_key)}
          event="disable_application"
          phx-value-key={@app.application_key}
        />
        <.application_lifecycle_action
          :if={@app.uninstallable?}
          action_id="uninstall"
          id={lifecycle_action_id("uninstall", @host_context, @app.application_key)}
          event="uninstall_application"
          phx-value-key={@app.application_key}
        />
      </div>
      <p :if={not @app.installable?} class="mt-5 text-xs text-base-content/50">
        This application is not available for installation in this deployment.
      </p>
    </.card>
    """
  end

  @spec dom_id(HostContext.t(), binary()) :: binary()
  def dom_id(%HostContext{placement: placement}, application_key)
      when is_binary(application_key) do
    "#{placement}-application-#{safe_application_key(application_key)}"
  end

  defp install_label(:disabled), do: "Enable"
  defp install_label(:uninstalled), do: "Reinstall"
  defp install_label(:installed), do: "Upgrade"
  defp install_label(_lifecycle_state), do: "Install"

  defp lifecycle_action_id(action, %HostContext{placement: placement}, application_key) do
    "#{action}-#{placement}-application-#{safe_application_key(application_key)}"
  end

  defp safe_application_key(key), do: String.replace(key, ~r/[^A-Za-z0-9_-]+/, "-")
end
