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
      <.hero_title>Sign in to Cadence</.hero_title>
      <.hero_copy>
        Enter your operator credentials to access the control plane.
      </.hero_copy>

      <.form_error message={Phoenix.Flash.get(@flash, :error)} />

      <.form
        for={@form}
        id="sign-in-form"
        action={~p"/sign-in"}
        phx-change="validate"
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

        <.button variant={:primary} kind={:submit} class="w-full">Sign In</.button>
      </.form>
    </.panel>
    """
  end
end
