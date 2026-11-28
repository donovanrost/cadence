defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole do
  @moduledoc "Phoenix-owned query provider for every route-level Ops surface."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, JSONBoundary, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole, as: OpsDefinition
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole.Presentation
  alias Cadence.Reads.OpsWorkspace.Landing

  @application_key "ops_console"
  @application_version 1
  @surface_version 1

  @impl true
  def application_key, do: @application_key

  @impl true
  def load(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: @application_key,
          application_version: @application_version,
          surface_id: surface_id,
          surface_version: @surface_version,
          query_id: query_id,
          query_version: 1,
          params: params
        }
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" and is_binary(surface_id) and is_map(params) do
    with {:ok, spec} <- spec(surface_id),
         true <- query_id == Map.get(spec, :query_id, "cadence.ops.#{surface_id}"),
         :ok <- validate_params(spec, params),
         :ok <- validate_mission_param(mission_id, params),
         :ok <- validate_scope_mission(scope, mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Cadence.Missions.fetch_mission(organization_id, mission_id),
         :ok <- validate_subject(spec.id, organization_id, mission_id, params),
         payload = dispatch(spec.id, scope, mission, params),
         {:ok, safe_payload} <- JSONBoundary.safe_trusted_output(payload) do
      {:ok, safe_payload}
    else
      false -> {:error, :unsupported_application_surface_query}
      {:error, :mission_not_found} -> {:error, :unsupported_application_surface_query}
      {:error, _reason} -> {:error, :unsupported_application_surface_query}
    end
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp spec(surface_id) do
    case Enum.find(OpsDefinition.surface_specs(), &(&1.id == surface_id)) do
      %{id: _id} = spec -> {:ok, spec}
      nil -> {:error, :unsupported_application_surface_query}
    end
  end

  defp validate_params(_spec, params) do
    allowed =
      MapSet.new([
        "mission_id",
        "dashboard_id",
        "version",
        "panel",
        "activity_filter",
        "activity_event",
        "selected_publish_issue",
        "share_id",
        "snapshot_id",
        "playlist_id",
        "data_source_id",
        "source_binding_id",
        "point_id",
        "spacecraft_id",
        "query",
        "severity",
        "state",
        "category",
        "kind",
        "from",
        "to",
        "limit",
        "index",
        "status",
        "target",
        "selected_time",
        "time_mode",
        "realm",
        "logical_source",
        "scope_id",
        "scope_kind",
        "sample_id",
        "replay_run_id",
        "selection_view",
        "time_axis",
        "validity_state",
        "question",
        "order",
        "limit_mode",
        "group"
      ])

    with true <- Enum.all?(Map.keys(params), &is_binary/1),
         true <- Enum.all?(Map.keys(params), &MapSet.member?(allowed, &1)),
         :ok <- JSONBoundary.validate(params) do
      :ok
    else
      _invalid -> {:error, :invalid_application_surface_query}
    end
  end

  defp validate_mission_param(mission_id, params) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      _other -> {:error, :scope_mismatch}
    end
  end

  defp validate_scope_mission(%Scope{mission_id: nil}, _mission_id), do: :ok
  defp validate_scope_mission(%Scope{mission_id: mission_id}, mission_id), do: :ok
  defp validate_scope_mission(%Scope{}, _mission_id), do: {:error, :scope_mismatch}

  defp validate_subject(surface_id, organization_id, mission_id, params)
       when surface_id in ["data_sources", "data_source_settings"] do
    case params["data_source_id"] do
      nil ->
        :ok

      source_id ->
        fetch_scoped_subject(
          Cadence.Reads.DataSources,
          :fetch_data_source,
          [source_id],
          organization_id,
          mission_id
        )
    end
  end

  defp validate_subject(_surface_id, _organization_id, _mission_id, _params), do: :ok

  defp fetch_scoped_subject(module, function, arguments, organization_id, mission_id) do
    case apply(module, function, arguments) do
      {:ok, subject} -> scope_subject(subject, organization_id, mission_id)
      _missing -> {:error, :subject_not_found}
    end
  rescue
    _exception -> {:error, :subject_not_found}
  end

  defp scope_subject(subject, organization_id, mission_id) do
    if Map.get(subject, :organization_id) in [nil, organization_id] and
         Map.get(subject, :mission_id) in [nil, mission_id],
       do: :ok,
       else: {:error, :subject_not_found}
  end

  defp dispatch("workspace", scope, mission, _params), do: landing(scope, mission)

  defp dispatch("data_sources", scope, mission, params),
    do: envelope("OpsDataSources", Presentation.data_sources(scope, mission, params, :reader))

  defp dispatch("data_source_registration", scope, mission, params),
    do:
      envelope("OpsDataSources", Presentation.data_sources(scope, mission, params, :registration))

  defp dispatch("data_source_settings", scope, mission, params),
    do: envelope("OpsDataSources", Presentation.data_sources(scope, mission, params, :settings))

  defp landing(scope, mission) do
    case Landing.load(scope, mission.mission_id) do
      {:ok, model} -> envelope("OpsConsoleLanding", %{"model" => model})
      _ -> throw(:workspace_unavailable)
    end
  end

  defp envelope(component, props),
    do: %{
      "navigation" => %{},
      "data" => %{
        "queryVersion" => 1,
        "presentation" => %{"component" => component, "props" => props}
      }
    }
end
