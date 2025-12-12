defmodule CadenceWeb.ProfileLive.Email do
  @moduledoc """
  LiveView for managing email address.

  Allows users to change their email address by sending
  a confirmation link to the new address.
  """
  use CadenceWeb, :live_view

  alias Cadence.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    changeset = Accounts.change_user_email(user)

    {:ok,
     socket
     |> assign(:page_title, "Email Settings")
     |> assign(:user, user)
     |> assign(:email_form, to_form(changeset))
     |> assign(:email_form_current_email, user.email)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :email_form, to_form(changeset))}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        {:noreply,
         socket
         |> put_flash(:info, "A link to confirm your email change has been sent to the new address.")
         |> assign(:email_form, to_form(Accounts.change_user_email(user)))}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(%{changeset | action: :insert}))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <.header>
        Email Settings
        <:subtitle>Manage your email address</:subtitle>
      </.header>

      <div class="mt-6">
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <h3 class="card-title text-base">Change Email Address</h3>
            <p class="text-sm text-base-content/60 mb-4">
              Your current email address is <span class="font-medium">{@email_form_current_email}</span>
            </p>

            <.simple_form
              for={@email_form}
              id="email_form"
              phx-change="validate_email"
              phx-submit="update_email"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label="New email address"
                placeholder="Enter your new email address"
                required
              />

              <:actions>
                <.button phx-disable-with="Sending...">
                  Update Email
                </.button>
              </:actions>
            </.simple_form>

            <p class="text-sm text-base-content/60 mt-4">
              A confirmation link will be sent to your new email address.
              Your email will not be changed until you click the link.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
