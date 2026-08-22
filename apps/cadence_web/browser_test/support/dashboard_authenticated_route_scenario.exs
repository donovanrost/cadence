Code.require_file("dashboard_rendered_viewport_support.exs", __DIR__)
Code.require_file("dashboard_authenticated_route_setup.exs", __DIR__)

defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteScenario do
  @moduledoc false

  alias CadenceWeb.Assets.DashboardAuthenticatedRouteSetup

  def run(sandbox_owner) do
    DashboardAuthenticatedRouteSetup.run(sandbox_owner, :current_ia)
  end
end
