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
    <div class="space-y-4">
      <%!-- Bespoke header: centered auth-layout branding, not a <.page_header> page. --%>
      <div class="text-center">
        <p class="text-primary tracking-[0.15em] text-sm font-semibold">
          &#9670; CADENCE
        </p>
        <h1 class="mt-3 text-xl font-bold text-base-content">Sign in</h1>
        <p class="text-xs text-base-content/50 mt-0.5">
          Enter your operator credentials to access the control plane.
        </p>
      </div>

      <.form
        for={@form}
        id="sign-in-form"
        action={~p"/sign-in"}
        phx-change="validate"
      >
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="operator@example.com"
          required
          autocomplete="email"
          autofocus
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          placeholder="Enter your password"
          required
          autocomplete="current-password"
        />

        <.button type="submit" size={:md} class="w-full mt-2">
          Sign In
        </.button>

        <p class="mt-3 text-center text-xs text-base-content/60">
          Need access? Contact your organization admin.
        </p>
      </.form>
    </div>
    """
  end
end
