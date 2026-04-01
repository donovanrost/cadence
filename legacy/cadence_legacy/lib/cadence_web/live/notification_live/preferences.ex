defmodule CadenceWeb.NotificationLive.Preferences do
  @moduledoc """
  LiveView for managing notification preferences.

  Users can configure how they receive notifications:
  - In-app notifications (on/off)
  - Email notifications (on/off)
  - Email frequency (immediate, daily digest, weekly digest)
  """
  use CadenceWeb, :live_view

  alias Cadence.Notifications

  @notification_types [
    %{
      type: "procedure_submitted",
      label: "Procedure Submitted",
      description: "When someone submits a procedure for your review"
    },
    %{
      type: "procedure_approved",
      label: "Procedure Approved",
      description: "When your procedure is approved by a reviewer"
    },
    %{
      type: "procedure_rejected",
      label: "Procedure Rejected",
      description: "When your procedure is rejected by a reviewer"
    },
    %{
      type: "procedure_finalized",
      label: "Procedure Finalized",
      description: "When a procedure receives all required approvals"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    preferences = load_preferences(user.id)

    {:ok,
     socket
     |> assign(:page_title, "Notification Preferences")
     |> assign(:notification_types, @notification_types)
     |> assign(:preferences, preferences)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp load_preferences(user_id) do
    Enum.map(@notification_types, fn type_info ->
      prefs = Notifications.get_preferences(user_id, type_info.type)

      Map.merge(type_info, %{
        in_app_enabled: prefs.in_app_enabled,
        email_enabled: prefs.email_enabled,
        email_frequency: prefs.email_frequency
      })
    end)
  end

  @impl true
  def handle_event("toggle_in_app", %{"type" => type, "value" => value}, socket) do
    user = socket.assigns.current_scope.user
    enabled = value == "true"

    case Notifications.set_preferences(user.id, type, %{in_app_enabled: enabled}) do
      {:ok, _pref} ->
        {:noreply,
         socket
         |> assign(:preferences, load_preferences(user.id))
         |> put_flash(:info, "Preference updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  def handle_event("toggle_email", %{"type" => type, "value" => value}, socket) do
    user = socket.assigns.current_scope.user
    enabled = value == "true"

    case Notifications.set_preferences(user.id, type, %{email_enabled: enabled}) do
      {:ok, _pref} ->
        {:noreply,
         socket
         |> assign(:preferences, load_preferences(user.id))
         |> put_flash(:info, "Preference updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  def handle_event("change_frequency", %{"type" => type, "frequency" => frequency}, socket) do
    user = socket.assigns.current_scope.user

    case Notifications.set_preferences(user.id, type, %{email_frequency: frequency}) do
      {:ok, _pref} ->
        {:noreply,
         socket
         |> assign(:preferences, load_preferences(user.id))
         |> put_flash(:info, "Preference updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.header>
        Notification Preferences
        <:subtitle>
          Choose how you want to be notified about activity in Cadence
        </:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <h3 class="card-title text-base">Procedure Approvals</h3>
            <p class="text-sm text-base-content/60 mb-4">
              Notifications about procedure review workflow activity
            </p>

            <div class="divide-y divide-base-300">
              <.preference_row
                :for={pref <- @preferences}
                type={pref.type}
                label={pref.label}
                description={pref.description}
                in_app_enabled={pref.in_app_enabled}
                email_enabled={pref.email_enabled}
                email_frequency={pref.email_frequency}
              />
            </div>
          </div>
        </div>

        <div class="card bg-base-200/50 border border-base-300">
          <div class="card-body">
            <h4 class="font-medium">Email Frequency Options</h4>
            <ul class="text-sm text-base-content/70 space-y-1 mt-2">
              <li>
                <span class="font-medium">Immediate</span>
                - Receive an email as soon as a notification is triggered
              </li>
              <li>
                <span class="font-medium">Daily Digest</span>
                - Receive a summary email once per day (8:00 AM UTC)
              </li>
              <li>
                <span class="font-medium">Weekly Digest</span>
                - Receive a summary email once per week (Monday 8:00 AM UTC)
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :in_app_enabled, :boolean, required: true
  attr :email_enabled, :boolean, required: true
  attr :email_frequency, :string, required: true

  defp preference_row(assigns) do
    ~H"""
    <div class="py-4 first:pt-0 last:pb-0">
      <div class="flex items-start justify-between gap-4">
        <div class="flex-1">
          <h4 class="font-medium">{@label}</h4>
          <p class="text-sm text-base-content/60">{@description}</p>
        </div>
      </div>

      <div class="mt-3 flex flex-wrap items-center gap-6">
        <!-- In-app toggle -->
        <div class="flex items-center gap-2">
          <label class="label cursor-pointer gap-2 p-0">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@in_app_enabled}
              phx-click="toggle_in_app"
              phx-value-type={@type}
              phx-value-value={if @in_app_enabled, do: "false", else: "true"}
            />
            <span class="label-text">In-app</span>
          </label>
        </div>
        
    <!-- Email toggle -->
        <div class="flex items-center gap-2">
          <label class="label cursor-pointer gap-2 p-0">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@email_enabled}
              phx-click="toggle_email"
              phx-value-type={@type}
              phx-value-value={if @email_enabled, do: "false", else: "true"}
            />
            <span class="label-text">Email</span>
          </label>
        </div>
        
    <!-- Email frequency dropdown -->
        <div class={["flex items-center gap-2", !@email_enabled && "opacity-50"]}>
          <span class="text-sm text-base-content/60">Frequency:</span>
          <select
            class="select select-sm select-bordered"
            disabled={!@email_enabled}
            phx-change="change_frequency"
            phx-value-type={@type}
            name="frequency"
          >
            <option value="immediate" selected={@email_frequency == "immediate"}>
              Immediate
            </option>
            <option value="daily_digest" selected={@email_frequency == "daily_digest"}>
              Daily Digest
            </option>
            <option value="weekly_digest" selected={@email_frequency == "weekly_digest"}>
              Weekly Digest
            </option>
          </select>
        </div>
      </div>
    </div>
    """
  end
end
