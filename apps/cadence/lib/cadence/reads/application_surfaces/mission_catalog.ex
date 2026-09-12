defmodule Cadence.Reads.ApplicationSurfaces.MissionCatalog do
  @moduledoc "Core-owned trusted read models for the Mission Catalog application."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{
    HostContext,
    SurfaceQueryRequest
  }

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Ids
  alias Cadence.Reads.Applications.Installations
  alias Cadence.Reads.Catalog.Pages
  alias Cadence.Reads.Missions.{CreationForm, Directory, Overview}

  @application_key "mission_catalog"
  @application_version 1
  @surface_version 1
  @max_param_keys 16

  @detail_params %{
    "catalog_database_show" => "catalog_database_id",
    "catalog_revision_show" => "catalog_revision_id",
    "catalog_artifact_show" => "artifact_id",
    "catalog_import_run_show" => "import_run_id"
  }

  @impl true
  def application_key, do: @application_key

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host_context, %SurfaceQueryRequest{} = request) do
    guarded(fn -> load_surface(scope, host_context, request) end)
  end

  defp load_surface(
         %Scope{organization_id: organization_id} = scope,
         %HostContext{} = host_context,
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
       when is_binary(organization_id) and organization_id != "" and is_map(params) do
    with :ok <- authorize_scope(scope, host_context),
         :ok <- validate_query_identity(surface_id, query_id),
         :ok <- validate_params(surface_id, params),
         {:ok, data} <- dispatch_surface(scope, host_context, surface_id, params),
         {:ok, safe_data} <- JSONBoundary.safe(data) do
      {:ok,
       %{
         "navigation" => navigation(host_context, surface_id, params),
         "data" => safe_data
       }}
    end
  end

  defp load_surface(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp authorize_scope(
         %Scope{} = scope,
         %HostContext{placement: :organization, organization_id: organization_id}
       )
       when is_binary(organization_id) do
    Policy.authorize(scope, :operate_organization, %{organization_id: organization_id})
  end

  defp authorize_scope(
         %Scope{} = scope,
         %HostContext{placement: :mission, mission_id: mission_id}
       )
       when is_binary(mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize_scope(_scope, _host_context),
    do: {:error, :unsupported_application_host_context}

  defp validate_query_identity(surface_id, query_id) do
    if is_binary(surface_id) and query_id == "cadence.mission_catalog." <> surface_id,
      do: :ok,
      else: {:error, :unsupported_application_surface_query}
  end

  defp validate_params(surface_id, params) do
    keys = Map.keys(params)

    cond do
      length(keys) > @max_param_keys -> {:error, :application_surface_bounds_exceeded}
      not Enum.all?(keys, &is_binary/1) -> {:error, :invalid_application_request}
      surface_id in Map.keys(@detail_params) -> validate_detail_params(surface_id, params)
      params == %{} -> :ok
      true -> {:error, :invalid_application_request}
    end
  end

  defp validate_detail_params(surface_id, params) do
    required = Map.fetch!(@detail_params, surface_id)

    if MapSet.new(Map.keys(params)) == MapSet.new([required]) do
      subject_id(params, required)
      |> case do
        {:ok, _id} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_application_request}
    end
  end

  defp subject_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case Ids.path_segment(value) do
          {:ok, value} -> {:ok, value}
          {:error, :invalid_identifier} -> {:error, :invalid_application_request}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp dispatch_surface(scope, %HostContext{placement: :organization}, "mission_list", _params),
    do: Directory.load(scope.organization_id)

  defp dispatch_surface(_scope, %HostContext{placement: :organization}, "mission_new", _params),
    do: {:ok, CreationForm.new()}

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "mission_overview",
         _params
       ),
       do: Overview.load(scope.organization_id, mission_id)

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         "mission_applications",
         _params
       ),
       do: Installations.load(scope, HostContext.mission(mission_id))

  defp dispatch_surface(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         surface,
         params
       )
       when surface in [
              "catalog_index",
              "catalog_database_new",
              "catalog_database_show",
              "catalog_revision_show",
              "catalog_artifact_show",
              "catalog_import_run_show"
            ] do
    Pages.load(scope, mission_id, surface, params)
  end

  defp dispatch_surface(_scope, _host_context, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp navigation(%HostContext{placement: :organization}, _surface_id, _params),
    do: %{"fallback_href" => "/missions"}

  defp navigation(%HostContext{mission_id: mission_id}, surface_id, params),
    do: %{
      "fallback_href" => "/missions/#{mission_id}",
      "surface_id" => surface_id,
      "params" => params
    }

  defp guarded(fun) do
    case fun.() do
      {:ok, _result} = result -> result
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_application_surface_provider_registry}
    end
  rescue
    _exception -> {:error, :invalid_application_surface_provider_registry}
  catch
    _kind, _value -> {:error, :invalid_application_surface_provider_registry}
  end
end
