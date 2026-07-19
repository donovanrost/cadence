Code.require_file("dashboard_rendered_viewport_support.exs", __DIR__)
Code.require_file("dashboard_authenticated_route_setup.exs", __DIR__)
Code.require_file("dashboard_authenticated_route_recovery.exs", __DIR__)
Code.require_file("dashboard_authenticated_route_worker_evidence.exs", __DIR__)
Code.require_file("dashboard_authenticated_route_replacement_evidence.exs", __DIR__)
Code.require_file("dashboard_authenticated_route_mixed_evidence.exs", __DIR__)

defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteScenario do
  @moduledoc false

  alias CadenceWeb.Assets.{
    DashboardAuthenticatedRouteMixedEvidence,
    DashboardAuthenticatedRouteRecovery,
    DashboardAuthenticatedRouteReplacementEvidence,
    DashboardAuthenticatedRouteSetup,
    DashboardAuthenticatedRouteWorkerEvidence
  }

  def run(sandbox_owner) do
    sandbox_owner
    |> DashboardAuthenticatedRouteSetup.run()
    |> DashboardAuthenticatedRouteRecovery.run()
    |> DashboardAuthenticatedRouteWorkerEvidence.run()
    |> DashboardAuthenticatedRouteReplacementEvidence.run()
    |> DashboardAuthenticatedRouteMixedEvidence.run()
  end
end
