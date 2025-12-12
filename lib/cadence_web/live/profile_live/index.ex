defmodule CadenceWeb.ProfileLive.Index do
  @moduledoc """
  LiveView for the profile overview page.

  Shows basic user information and serves as a placeholder
  for future profile-related features.
  """
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Profile")
     |> assign(:user, user)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <.header>
        Profile
        <:subtitle>Your account information</:subtitle>
      </.header>

      <div class="mt-6 space-y-6">
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <h3 class="card-title text-base">Account Information</h3>

            <dl class="mt-4 space-y-4">
              <div>
                <dt class="text-sm text-base-content/60">Email Address</dt>
                <dd class="mt-1 font-medium">{@user.email}</dd>
              </div>

              <div>
                <dt class="text-sm text-base-content/60">Member Since</dt>
                <dd class="mt-1 font-medium">{format_date(@user.inserted_at)}</dd>
              </div>

              <div>
                <dt class="text-sm text-base-content/60">Role</dt>
                <dd class="mt-1">
                  <span class={[
                    "badge",
                    @user.system_admin && "badge-accent",
                    !@user.system_admin && "badge-ghost"
                  ]}>
                    {if @user.system_admin, do: "System Admin", else: String.capitalize(@user.role)}
                  </span>
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <div class="card bg-base-200/50 border border-base-300">
          <div class="card-body">
            <h4 class="font-medium">Quick Links</h4>
            <ul class="mt-2 space-y-2 text-sm">
              <li>
                <.link navigate={~p"/profile/email"} class="link link-hover">
                  Change your email address
                </.link>
              </li>
              <li>
                <.link navigate={~p"/profile/notifications"} class="link link-hover">
                  Manage notification preferences
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end
end
