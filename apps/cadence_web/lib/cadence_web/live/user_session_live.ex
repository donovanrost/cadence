defmodule CadenceWeb.UserSessionLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    params = %{"email" => "", "password" => ""}

    {:ok,
     socket
     |> assign(:form, to_form(params, as: :user))
     |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token_for(~p"/sign-in"))
     |> assign(:page_title, "Sign in")}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.vue
      id="user-session-component"
      v-component="UserSession"
      page={page_dto()}
      form={form_dto(@form, @csrf_token)}
      v-on:validate={JS.push("validate")}
      v-ssr={false}
    />
    """
  end

  defp page_dto do
    %{
      id: "user-session-page",
      brand: "◆ CADENCE",
      heading: "Sign in",
      body: "Enter your operator credentials to access the control plane.",
      access_help: "Need access? Contact your organization admin."
    }
  end

  defp form_dto(form, csrf_token) do
    %{
      id: "sign-in-form",
      action: ~p"/sign-in",
      method: "post",
      csrf: %{name: "_csrf_token", value: csrf_token},
      fields: %{
        email: %{
          id: "user_email",
          name: "user[email]",
          type: "email",
          label: "Email",
          placeholder: "operator@example.com",
          required: true,
          autocomplete: "email",
          autofocus: true,
          value: form_value(form, :email)
        },
        password: %{
          id: "user_password",
          name: "user[password]",
          type: "password",
          label: "Password",
          placeholder: "Enter your password",
          required: true,
          autocomplete: "current-password",
          autofocus: false,
          value: form_value(form, :password)
        }
      },
      submit: %{id: "sign-in-submit", label: "Sign In"}
    }
  end

  defp form_value(form, field), do: Form.input_value(form, field) || ""
end
