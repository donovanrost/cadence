defmodule CadenceWeb.SettingsLive.Index do
  @moduledoc """
  LiveView for organization settings management.

  Provides a tabbed interface for configuring organization-level defaults
  that apply to all missions within the organization.
  """
  use CadenceWeb, :live_view

  alias Cadence.Settings

  import CadenceWeb.SettingsComponents

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
    settings = Settings.get_all_org_settings(org, :procedures)

    socket
    |> assign(:page_title, "Settings - Procedures")
    |> assign(:organization, org)
    |> assign(:active_tab, :procedures)
    |> assign(:settings, settings)
  end

  @impl true
  def handle_event("save_setting", %{} = params, socket) do
    org = socket.assigns.organization
    key = extract_setting_key(params)
    value = extract_setting_value(params)

    key_atom = String.to_existing_atom(key)
    parsed_value = parse_value(key_atom, value)

    case Settings.set_org(org, :procedures, key_atom, parsed_value) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> put_flash(:info, "Setting updated")
         |> assign(:settings, Settings.get_all_org_settings(org, :procedures))}

      {:error, :invalid_value} ->
        {:noreply, put_flash(socket, :error, "Invalid value")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save setting")}
    end
  end

  def handle_event("increment_setting", %{"name" => name}, socket) do
    org = socket.assigns.organization
    key_atom = String.to_existing_atom(name)
    current_value = Settings.get_org(org, :procedures, key_atom)
    definition = Settings.get_definition(:procedures, key_atom)

    max_value =
      case definition.validate do
        {:range, _, max} -> max
        _ -> nil
      end

    new_value =
      if max_value && current_value >= max_value do
        current_value
      else
        current_value + 1
      end

    case Settings.set_org(org, :procedures, key_atom, new_value) do
      {:ok, _setting} ->
        {:noreply, assign(socket, :settings, Settings.get_all_org_settings(org, :procedures))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting")}
    end
  end

  def handle_event("decrement_setting", %{"name" => name}, socket) do
    org = socket.assigns.organization
    key_atom = String.to_existing_atom(name)
    current_value = Settings.get_org(org, :procedures, key_atom)
    definition = Settings.get_definition(:procedures, key_atom)

    min_value =
      case definition.validate do
        {:range, min, _} -> min
        _ -> nil
      end

    new_value =
      if min_value && current_value <= min_value do
        current_value
      else
        current_value - 1
      end

    case Settings.set_org(org, :procedures, key_atom, new_value) do
      {:ok, _setting} ->
        {:noreply, assign(socket, :settings, Settings.get_all_org_settings(org, :procedures))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting")}
    end
  end

  defp extract_setting_key(params) do
    # Handle both direct key and nested form params
    cond do
      Map.has_key?(params, "key") -> params["key"]
      Map.has_key?(params, "_target") -> List.first(params["_target"])
      true -> nil
    end
  end

  defp extract_setting_value(params) do
    # Handle both direct value and nested form params
    if Map.has_key?(params, "value") do
      params["value"]
    else
      Map.get(params, extract_setting_key(params))
    end
  end

  defp parse_value(key, value) do
    definition = Settings.get_definition(:procedures, key)

    case definition.type do
      :integer when is_binary(value) -> String.to_integer(value)
      :integer -> value
      :boolean when is_binary(value) -> value == "true"
      :boolean -> value
      :string -> value
    end
  end

  defp get_min_value(setting) do
    case setting.validate do
      {:range, min, _max} -> min
      _ -> nil
    end
  end

  defp get_max_value(setting) do
    case setting.validate do
      {:range, _min, max} -> max
      _ -> nil
    end
  end

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
                      min={get_min_value(setting)}
                      max={get_max_value(setting)}
                      name={to_string(setting.key)}
                      phx-change="save_setting"
                    />
                  <% else %>
                    <.setting_toggle
                      value={setting.value}
                      name={to_string(setting.key)}
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
