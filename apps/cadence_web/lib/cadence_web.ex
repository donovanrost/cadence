defmodule CadenceWeb do
  @moduledoc false

  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json], layouts: [html: CadenceWeb.Layouts]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {CadenceWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def endpoint do
    quote do
      use Phoenix.Endpoint, otp_app: :cadence_web
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import CadenceWeb.CoreComponents
      import CadenceWeb.UI

      alias CadenceWeb.Layouts

      unquote(verified_routes())
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defp verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: CadenceWeb.Endpoint,
        router: CadenceWeb.Router,
        statics: CadenceWeb.static_paths()
    end
  end
end
