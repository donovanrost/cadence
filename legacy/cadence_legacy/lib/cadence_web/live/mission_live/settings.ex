defmodule CadenceWeb.MissionLive.Settings do
  @moduledoc """
  LiveView for managing mission-level settings.

  This page allows overriding organization defaults with mission-specific
  values that must be at least as restrictive as the org defaults.
  """
  use CadenceWeb, :live_view

  import CadenceWeb.SettingsComponents

  alias Cadence.Settings

  @impl true
  def mount(_params, _session, socket) do
    # Mission is already loaded via :load_mission hook in router
    {:ok, assign(socket, :errors, %{})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Mission Settings")
    |> assign(:active_tab, :general)
  end

  defp apply_action(socket, :general, _params) do
    socket
    |> assign(:page_title, "Mission Settings")
    |> assign(:active_tab, :general)
  end

  defp apply_action(socket, :procedures, _params) do
    mission = socket.assigns.mission
    settings = Settings.get_all_mission_settings(mission, :procedures)

    socket
    |> assign(:page_title, "Mission Settings - Procedures")
    |> assign(:active_tab, :procedures)
    |> assign(:settings, settings)
  end

  @impl true
  def handle_event("increment_setting", %{"name" => name}, socket) do
    mission = socket.assigns.mission
    key_atom = String.to_existing_atom(name)
    setting = Enum.find(socket.assigns.settings, &(&1.key == key_atom))

    new_value = setting.effective_value + 1

    save_setting_value(socket, mission, key_atom, new_value)
  end

  @impl true
  def handle_event("decrement_setting", %{"name" => name}, socket) do
    mission = socket.assigns.mission
    key_atom = String.to_existing_atom(name)
    setting = Enum.find(socket.assigns.settings, &(&1.key == key_atom))

    new_value = setting.effective_value - 1

    save_setting_value(socket, mission, key_atom, new_value)
  end

  @impl true
  def handle_event("save_setting", params, socket) do
    mission = socket.assigns.mission

    # Extract key from _target (the field that triggered the change) or find non-internal key
    key =
      if Map.has_key?(params, "_target") do
        List.first(params["_target"])
      else
        params
        |> Map.keys()
        |> Enum.find(fn k -> is_binary(k) and not String.starts_with?(k, "_") end) || ""
      end

    value = Map.get(params, key, "")

    key_atom = String.to_existing_atom(key)
    parsed_value = parse_value(key_atom, value)

    save_setting_value(socket, mission, key_atom, parsed_value)
  end

  defp save_setting_value(socket, mission, key_atom, value) do
    case Settings.set_mission(mission, :procedures, key_atom, value) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:settings, Settings.get_all_mission_settings(mission, :procedures))
         |> assign(:errors, Map.delete(socket.assigns.errors, key_atom))
         |> put_flash(:info, "Setting updated")}

      {:error, :less_restrictive_than_org, details} ->
        error_msg = restrictiveness_error_message(key_atom, details)

        {:noreply,
         socket
         |> assign(:errors, Map.put(socket.assigns.errors, key_atom, error_msg))}

      {:error, :invalid_value} ->
        {:noreply,
         socket
         |> assign(:errors, Map.put(socket.assigns.errors, key_atom, "Invalid value"))}
    end
  end

  defp parse_value(key, value) when is_binary(value) do
    definition = Settings.get_definition(:procedures, key)

    case definition.type do
      :integer -> String.to_integer(value)
      :boolean -> value == "true"
      :string -> value
    end
  end

  defp parse_value(_key, value), do: value

  defp restrictiveness_error_message(key, %{org_value: org_value}) do
    definition = Settings.get_definition(:procedures, key)

    case definition.restrictiveness do
      :higher -> "Must be at least #{org_value}"
      :lower -> "Must be at most #{org_value}"
      :false_is_stricter -> "Cannot enable - disabled at organization level"
      _ -> "Value not allowed"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <%= if @active_tab == :general do %>
        <.header>
          General Settings
          <:subtitle>Mission information</:subtitle>
        </.header>

        <div class="mt-6">
          <.settings_section title="Mission Information">
            <div class="card bg-base-100 border border-base-300 p-4">
              <dl class="space-y-2">
                <div>
                  <dt class="text-sm text-base-content/60">Name</dt>
                  <dd class="font-medium">{@mission.name}</dd>
                </div>
                <div>
                  <dt class="text-sm text-base-content/60">Status</dt>
                  <dd class="font-medium">{@mission.status}</dd>
                </div>
              </dl>
            </div>
          </.settings_section>
        </div>
      <% else %>
        <.header>
          Procedures Settings
          <:subtitle>Override organization defaults for procedure approvals</:subtitle>
        </.header>

        <div class="mt-6">
          <.settings_section title="Approval Workflow">
            <%= for setting <- @settings do %>
              <.setting_override_card
                label={setting.label}
                description={setting.description}
                type={setting.type}
                org_value={setting.org_value}
                effective_value={setting.effective_value}
                min_value={setting.min_value}
                max_value={setting.max_value}
                restrictiveness={setting.restrictiveness}
                name={setting.key}
                error={Map.get(@errors, setting.key)}
                can_override={setting.can_override}
                phx-change="save_setting"
              />
            <% end %>
          </.settings_section>
        </div>
      <% end %>
    </div>
    """
  end
end
