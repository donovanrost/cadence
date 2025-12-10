defmodule CadenceWeb.SettingsLive.Index do
  @moduledoc """
  LiveView for organization settings management.

  Provides a tabbed interface for configuring organization-level defaults
  that apply to all missions within the organization.
  """
  use CadenceWeb, :live_view

  alias Cadence.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :general, _params) do
    org = socket.assigns.current_scope.current_organization

    socket
    |> assign(:page_title, "Settings")
    |> assign(:organization, org)
    |> assign(:active_tab, :general)
  end

  defp apply_action(socket, :procedures, _params) do
    org = socket.assigns.current_scope.current_organization
    settings = load_procedure_settings(org)

    socket
    |> assign(:page_title, "Settings - Procedures")
    |> assign(:organization, org)
    |> assign(:active_tab, :procedures)
    |> assign(:settings, settings)
  end

  defp load_procedure_settings(org) do
    Settings.list_definitions(:procedures)
    |> Enum.map(fn definition ->
      %{
        key: definition.key,
        label: definition.label,
        description: definition.description,
        type: definition.type,
        value: Settings.get_org(org, :procedures, definition.key),
        restrictiveness: definition.restrictiveness,
        validate: definition.validate
      }
    end)
  end

  @impl true
  def handle_event("save_setting", %{"key" => key, "value" => value}, socket) do
    org = socket.assigns.organization
    key_atom = String.to_existing_atom(key)

    parsed_value = parse_value(key_atom, value)

    case Settings.set_org(org, :procedures, key_atom, parsed_value) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting updated")
         |> assign(:settings, load_procedure_settings(org))}

      {:error, :invalid_value} ->
        {:noreply, put_flash(socket, :error, "Invalid value")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save setting")}
    end
  end

  defp parse_value(key, value) do
    definition = Settings.get_definition(:procedures, key)

    case definition.type do
      :integer -> String.to_integer(value)
      :boolean -> value == "true"
      :string -> value
    end
  end

  defp restrictiveness_hint(:higher), do: "Missions can require more, but not fewer"
  defp restrictiveness_hint(:lower), do: "Missions can set lower values, but not higher"

  defp restrictiveness_hint(:false_is_stricter),
    do: "Missions can disable this, but cannot re-enable if disabled here"

  defp restrictiveness_hint(:none), do: "Missions can override with any valid value"
  defp restrictiveness_hint(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Settings
      <:subtitle>Configure organization defaults for all missions</:subtitle>
    </.header>

    <div class="mt-6">
      <.settings_layout>
        <:tabs>
          <.settings_tab
            navigate={~p"/settings"}
            active={@active_tab == :general}
            icon="hero-building-office"
          >
            General
          </.settings_tab>
          <.settings_tab
            navigate={~p"/settings/procedures"}
            active={@active_tab == :procedures}
            icon="hero-document-text"
          >
            Procedures
          </.settings_tab>
        </:tabs>
        <:content>
          <%= if @active_tab == :general do %>
            <.settings_section title="Organization">
              <div class="card bg-base-100 border border-base-300 p-4">
                <dl class="space-y-2">
                  <div>
                    <dt class="text-sm text-base-content/60">Name</dt>
                    <dd class="font-medium">{@organization.name}</dd>
                  </div>
                  <div>
                    <dt class="text-sm text-base-content/60">Slug</dt>
                    <dd class="font-medium font-mono">{@organization.slug}</dd>
                  </div>
                </dl>
              </div>
            </.settings_section>
          <% else %>
            <.settings_section
              title="Approval Workflow"
              description="Configure how procedure versions are reviewed and approved"
            >
              <%= for setting <- @settings do %>
                <.setting_card
                  label={setting.label}
                  description={setting.description}
                  hint={restrictiveness_hint(setting.restrictiveness)}
                >
                  <%= if setting.type == :integer do %>
                    <.setting_number_input
                      value={setting.value}
                      min={elem(setting.validate, 1)}
                      max={elem(setting.validate, 2)}
                      name={setting.key}
                      phx-change="save_setting"
                    />
                  <% else %>
                    <.setting_toggle
                      value={setting.value}
                      name={setting.key}
                      phx-change="save_setting"
                    />
                  <% end %>
                </.setting_card>
              <% end %>
            </.settings_section>
          <% end %>
        </:content>
      </.settings_layout>
    </div>
    """
  end
end
