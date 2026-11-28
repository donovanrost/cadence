defmodule CadenceWeb.Console.APIV1RoutingTest do
  @moduledoc """
  #747: `/api/v1` is Cadence's one public API. Every route in it passes the console API's
  authentication pipeline, and every mission- or organization-scoped route passes its scope plug,
  whatever credential the request carries. A route mounted outside these pipelines (for example
  a bearer-only scope beside them) fails here.
  """
  use ExUnit.Case, async: true

  # The four signed-out routes: sign-in and invitation links.
  @signed_out ~w(/api/v1/auth/sign-in /api/v1/auth/invitations/:token
                 /api/v1/auth/invitations/:token/accept /api/v1/auth/invitations/:token/decline)

  # Each route with the pipelines it actually passes, resolved through the router as a request
  # for it would be (path params filled with a placeholder).
  defp api_v1_routes do
    for route <- CadenceWeb.Router.__routes__(),
        String.starts_with?(route.path, "/api/v1/") do
      verb = route.verb |> Atom.to_string() |> String.upcase()
      path = String.replace(route.path, ~r{/[:*][^/]+}, "/x")
      info = Phoenix.Router.route_info(CadenceWeb.Router, verb, path, "localhost")

      %{verb: verb, path: route.path, resolved: info.route, pipe_through: info.pipe_through}
    end
  end

  # The one machine surface that is not the public API: release publishing (being deleted, #672).
  @other_api ~w(/api/cadence/frontend-release/v1/)

  # #708 / #747: the pre-console REST API (`/api/organizations/:id/…`: stages, requests, approvals,
  # queue entries, release attempts, verifier instances, service identities, missions) is gone, and
  # nothing comes back under a new `/api` path. One check in place of a 404 test per old route.
  test "every /api route is /api/v1, or the named machine surface" do
    offenders =
      for route <- CadenceWeb.Router.__routes__(),
          String.starts_with?(route.path, "/api"),
          not String.starts_with?(route.path, "/api/v1/"),
          not Enum.any?(@other_api, &String.starts_with?(route.path, &1)),
          do: {route.verb, route.path}

    assert offenders == []
  end

  test "the public API has routes, and each resolves to itself" do
    routes = api_v1_routes()
    assert length(routes) > 100
    assert Enum.reject(routes, &(&1.resolved == &1.path)) == []
  end

  test "every /api/v1 route is authenticated by the console API pipeline" do
    offenders =
      for route <- api_v1_routes(),
          expected = if(route.path in @signed_out, do: :console_auth_api, else: :console_api),
          expected not in route.pipe_through,
          do: {route.verb, route.path, route.pipe_through}

    assert offenders == []
  end

  test "the signed-out pipeline serves only sign-in and invitation links" do
    signed_out =
      for route <- api_v1_routes(),
          :console_auth_api in route.pipe_through,
          uniq: true,
          do: route.path

    assert Enum.sort(signed_out) == Enum.sort(@signed_out)
  end

  test "mission and organization routes pass their scope plugs" do
    offenders =
      for route <- api_v1_routes(),
          {prefix, plug} <- [
            {"/api/v1/missions/:mission_id", :console_mission},
            {"/api/v1/organizations/:organization_id", :console_organization}
          ],
          String.starts_with?(route.path, prefix),
          plug not in route.pipe_through,
          do: {route.verb, route.path, plug}

    assert offenders == []
  end
end
