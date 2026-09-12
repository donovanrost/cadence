defmodule Cadence.Reads.ApplicationSurfaces.Spacecraft do
  @moduledoc "Core-owned trusted DTO provider for the federated Spacecraft application."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{
    HostContext,
    JSONBoundary,
    SurfaceQueryContribution,
    SurfaceQueryRequest
  }

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions
  alias Cadence.Reads.Applications.Installations
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.Configuration, as: DecomConfiguration
  alias Cadence.Reads.Comms.SpacecraftRouting
  alias Cadence.Reads.Spacecraft.Pages
  alias Cadence.SpacecraftStore

  @application_key "spacecraft"
  @application_version 1
  @surface_version 1
  @max_map_keys 32

  @surface_queries %{
    "list" => "cadence.spacecraft.list",
    "new" => "cadence.spacecraft.new",
    "profile_list" => "cadence.spacecraft.profiles",
    "profile_new" => "cadence.spacecraft.profile.new",
    "profile_show" => "cadence.spacecraft.profile.show",
    "show" => "cadence.spacecraft.show",
    "edit" => "cadence.spacecraft.edit",
    "readiness" => "cadence.spacecraft.readiness",
    "routing" => "cadence.spacecraft.routing",
    "commanding" => "cadence.spacecraft.commanding",
    "applications" => "cadence.spacecraft.applications",
    "telemetry_decom" => "cadence.telemetry_decom.manage"
  }

  @mission_surfaces Map.keys(@surface_queries) --
                      [
                        "show",
                        "edit",
                        "readiness",
                        "routing",
                        "commanding",
                        "applications",
                        "telemetry_decom"
                      ]
  @spacecraft_surfaces Map.keys(@surface_queries) -- @mission_surfaces

  @impl true
  def application_key, do: @application_key

  @doc "Returns the authoritative provider map entries owned by Spacecraft."
  @spec contributions() :: [SurfaceQueryContribution.t()]
  def contributions do
    @surface_queries
    |> Map.delete("telemetry_decom")
    |> Enum.map(fn {_surface_id, query_id} ->
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: @application_version,
        query_id: query_id,
        query_version: @surface_version,
        provider: __MODULE__
      }
    end)
    |> Enum.sort_by(& &1.query_id)
  end

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host_context, %SurfaceQueryRequest{} = request) do
    guarded(fn -> load_surface(scope, host_context, request) end)
  end

  defp load_surface(
         %Scope{organization_id: organization_id, mission_id: scope_mission_id} = scope,
         %HostContext{placement: placement, mission_id: mission_id} = host_context,
         %SurfaceQueryRequest{
           application_key: @application_key,
           application_version: @application_version,
           surface_version: @surface_version,
           query_version: @surface_version,
           surface_id: surface_id,
           query_id: query_id,
           params: params
         }
       )
       when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
              mission_id != "" and is_map(params) and placement in [:mission, :spacecraft] and
              (is_nil(scope_mission_id) or scope_mission_id == mission_id) do
    with :ok <- validate_surface_scope(surface_id, placement),
         :ok <- validate_query_identity(surface_id, query_id),
         :ok <- validate_params(surface_id, params),
         :ok <- authorize(scope, mission_id),
         {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         :ok <- ensure_mission_scope(mission, organization_id, mission_id),
         {:ok, data} <- dispatch_surface(scope, host_context, mission, surface_id, params),
         {:ok, safe_data} <- JSONBoundary.safe(data) do
      {:ok,
       %{
         "navigation" => navigation(surface_id, mission_id, host_context),
         "data" => safe_data
       }}
    end
  end

  defp load_surface(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp dispatch_surface(scope, _host_context, mission, "list", params),
    do: Pages.load(scope, "spacecraft_list", mission.mission_id, params)

  defp dispatch_surface(scope, _host_context, mission, "new", _params),
    do: Pages.load(scope, "spacecraft_new", mission.mission_id, %{})

  defp dispatch_surface(scope, _host_context, mission, "profile_list", _params),
    do: Pages.load(scope, "profile_list", mission.mission_id, %{})

  defp dispatch_surface(scope, _host_context, mission, "profile_new", params),
    do: Pages.load(scope, "profile_new", mission.mission_id, params)

  defp dispatch_surface(scope, _host_context, mission, "profile_show", params),
    do: Pages.load(scope, "profile_show", mission.mission_id, params)

  defp dispatch_surface(scope, host_context, mission, "show", _params),
    do:
      Pages.load(scope, "spacecraft_show", mission.mission_id, %{
        "spacecraft_id" => host_context.spacecraft_id
      })

  defp dispatch_surface(scope, host_context, mission, "edit", _params),
    do:
      Pages.load(scope, "spacecraft_edit", mission.mission_id, %{
        "spacecraft_id" => host_context.spacecraft_id
      })

  defp dispatch_surface(scope, host_context, mission, "readiness", _params),
    do:
      Pages.load(scope, "spacecraft_readiness", mission.mission_id, %{
        "spacecraft_id" => host_context.spacecraft_id
      })

  defp dispatch_surface(scope, host_context, mission, "routing", _params),
    do: SpacecraftRouting.load(scope, mission.mission_id, host_context.spacecraft_id)

  defp dispatch_surface(_scope, host_context, mission, "commanding", _params),
    do: commanding_destination(host_context, mission)

  defp dispatch_surface(scope, host_context, _mission, "applications", _params),
    do: Installations.load(scope, host_context)

  defp dispatch_surface(scope, host_context, mission, "telemetry_decom", _params),
    do:
      DecomConfiguration.load(
        scope,
        host_context,
        mission
      )

  defp dispatch_surface(_scope, _host_context, _mission, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp commanding_destination(host_context, mission) do
    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             mission.organization_id,
             mission.mission_id,
             host_context.spacecraft_id
           ) do
      {:ok, %{"mission_id" => mission.mission_id, "spacecraft_id" => spacecraft.spacecraft_id}}
    end
  end

  defp validate_surface_scope(surface_id, :mission) when surface_id in @mission_surfaces, do: :ok

  defp validate_surface_scope(surface_id, :spacecraft) when surface_id in @spacecraft_surfaces,
    do: :ok

  defp validate_surface_scope(_surface_id, _placement),
    do: {:error, :unsupported_application_host_context}

  defp validate_query_identity(surface_id, query_id) do
    if Map.get(@surface_queries, surface_id) == query_id,
      do: :ok,
      else: {:error, :unsupported_application_surface_query}
  end

  defp validate_params("list", params) do
    validate_param_keys(params, ~w(q sort dir page pageSize filter))
  end

  defp validate_params("profile_show", params), do: validate_param_keys(params, ["profile_id"])
  defp validate_params(_surface_id, params), do: validate_param_keys(params, [])

  defp validate_param_keys(params, allowed) do
    keys = Map.keys(params)

    cond do
      length(keys) > @max_map_keys -> {:error, :application_surface_bounds_exceeded}
      not Enum.all?(keys, &is_binary/1) -> {:error, :invalid_application_request}
      MapSet.subset?(MapSet.new(keys), MapSet.new(allowed)) -> :ok
      true -> {:error, :invalid_application_request}
    end
  end

  defp authorize(scope, mission_id),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })

  defp ensure_mission_scope(
         %{organization_id: organization_id, mission_id: mission_id},
         organization_id,
         mission_id
       ),
       do: :ok

  defp ensure_mission_scope(_mission, _organization_id, _mission_id),
    do: {:error, :unsupported_application_surface_query}

  defp navigation(surface_id, mission_id, %HostContext{placement: :mission}) do
    %{
      "fallback_href" => "#{mission_path_id(mission_id)}/spacecraft",
      "breadcrumbs" => [
        %{"label" => "Mission", "href" => mission_path_id(mission_id)},
        %{"label" => surface_label(surface_id), "href" => nil}
      ]
    }
  end

  defp navigation(surface_id, mission_id, %HostContext{
         placement: :spacecraft,
         spacecraft_id: spacecraft_id
       }) do
    %{
      "fallback_href" =>
        "#{mission_path_id(mission_id)}/spacecraft/#{spacecraft_id}/#{surface_id}",
      "breadcrumbs" => [
        %{"label" => "Mission", "href" => mission_path_id(mission_id)},
        %{"label" => "Spacecraft", "href" => "#{mission_path_id(mission_id)}/spacecraft"},
        %{"label" => surface_label(surface_id), "href" => nil}
      ]
    }
  end

  defp mission_path_id(mission_id), do: "/missions/#{mission_id}"

  defp surface_label("list"), do: "Spacecraft"
  defp surface_label("new"), do: "New Spacecraft"
  defp surface_label("profile_list"), do: "Profiles"
  defp surface_label("profile_new"), do: "New Profile"
  defp surface_label("profile_show"), do: "Profile"
  defp surface_label("show"), do: "Overview"
  defp surface_label("edit"), do: "Identity"
  defp surface_label("readiness"), do: "Readiness"
  defp surface_label("routing"), do: "Routing"
  defp surface_label("commanding"), do: "Commanding"
  defp surface_label("applications"), do: "Applications"
  defp surface_label("telemetry_decom"), do: "Telemetry Decom"

  defp guarded(fun) do
    fun.()
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    :throw, :invalid_application_request -> {:error, :invalid_application_request}
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end
end
