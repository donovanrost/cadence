defmodule CadenceWeb do
  @moduledoc false

  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def endpoint do
    quote do
      use Phoenix.Endpoint, otp_app: :cadence_web
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
