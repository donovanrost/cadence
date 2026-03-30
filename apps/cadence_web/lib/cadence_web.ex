defmodule CadenceWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json], layouts: []

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def router do
    quote do
      use Phoenix.Router
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
        statics: []
    end
  end
end
