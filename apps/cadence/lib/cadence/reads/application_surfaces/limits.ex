defmodule Cadence.Reads.ApplicationSurfaces.Limits do
  @moduledoc "Scoped semantic feature queries for governed definitions and evaluated limit posture."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider
  alias Cadence.Applications.{ApplicationInstallations, HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Limits.{Definitions, Pages, Posture}
  @impl true
  def application_key, do: "limits"
  @impl true
  def load(%Scope{} = scope, %HostContext{placement: :mission} = host, %SurfaceQueryRequest{
        application_key: "limits",
        application_version: 1,
        surface_id: surface,
        surface_version: 1,
        query_id: query_id,
        query_version: 1,
        params: params
      })
      when surface in ["manage", "activity"] do
    with true <- query_id == "cadence.limits.#{surface}",
         {:ok, query} <- Pages.parse(params),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, host.mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: host.mission_id
           }),
         {:ok, actor} <- actor(scope),
         {:ok, installation} <- ApplicationInstallations.fetch_installed(scope, host, "limits"),
         {:ok, feature} <- feature(surface, scope.organization_id, host.mission_id, query) do
      base = "/missions/#{host.mission_id}/applications/limits"

      data =
        Map.merge(feature, %{
          "contract_version" => 1,
          "surface" => surface,
          "context" => %{
            "organization_id" => scope.organization_id,
            "mission_id" => host.mission_id,
            "actor_id" => actor,
            "installation_id" => installation.application_installation_id
          },
          "mission_name" => mission.display_name,
          "query" => query,
          "links" => %{
            "self" => base <> "/" <> surface,
            "manage" => base <> "/manage",
            "activity" => base <> "/activity",
            "applications" => "/missions/#{host.mission_id}/applications"
          }
        })

      {:ok,
       %{
         "data" => data,
         "navigation" => %{"fallback_href" => data["links"]["applications"], "breadcrumbs" => []}
       }}
    else
      false -> {:error, :unsupported_application_surface_query}
      {:error, _} = error -> error
    end
  end

  def load(_, _, _), do: {:error, :unsupported_application_surface_query}
  defp feature("manage", org, mission, query), do: Definitions.load(org, mission, query)
  defp feature("activity", org, mission, query), do: Posture.load(org, mission, query)
  defp actor(%Scope{actor_kind: :user, user: %{user_id: id}}), do: {:ok, id}

  defp actor(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}}),
    do: {:ok, id}

  defp actor(_), do: {:error, :forbidden}
end
