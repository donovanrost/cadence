defmodule CadenceWeb.UserSessionLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user))
     |> assign(:page_title, "Sign in")}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.panel variant={:hero}>
      <.eyebrow>Cadence Access</.eyebrow>
      <.hero_title>Sign in to Cadence.</.hero_title>
      <.hero_copy>
        Enter the credentials for your Cadence operator account. During first-run setup,
        the same form accepts the temporary setup-access credentials configured for this
        deployment.
      </.hero_copy>

      <.form_error message={Phoenix.Flash.get(@flash, :error)} />

      <.form
        for={@form}
        id="sign-in-form"
        action={~p"/sign-in"}
        phx-change="validate"
        phx-trigger-action={false}
        class="grid gap-4"
      >
        <.text_field
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="operator@example.com"
          required
          autocomplete="email"
          autofocus
        />
        <.text_field
          field={@form[:password]}
          type="password"
          label="Password"
          placeholder="Enter your password"
          required
          autocomplete="current-password"
        />

        <div class="flex items-center justify-between gap-4 flex-wrap">
          <.button variant={:primary} kind={:submit}>Sign In</.button>
          <p class="m-0 text-muted leading-[1.6] text-sm">
            Invitation acceptance creates the durable account. Public self-signup remains closed.
          </p>
        </div>
      </.form>
    </.panel>
    """
  end
end
