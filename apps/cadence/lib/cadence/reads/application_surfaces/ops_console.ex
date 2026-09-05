defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole do
  @moduledoc "Bounded Phoenix-owned query contribution for the federated Ops Console."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, JSONBoundary, SurfaceQueryRequest}
  alias Cadence.Auth.{Policy, Scope}

  @application_key "ops_console"
  @application_version 1
  @surface_version 1
  @query_ids %{
    "workspace" => "cadence.ops.workspace",
    "ops" => "cadence.ops.console"
  }

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
             mission_id != "" and is_map(params) do
    with {:ok, expected_query_id} <- Map.fetch(@query_ids, surface_id),
         true <- expected_query_id == query_id,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         :ok <- JSONBoundary.validate(params) do
      presentation = %{
        "component" => "OpsConsoleLanding",
        "props" => %{
          "missionId" => mission_id,
          "missionName" => mission_name(scope, mission_id),
          "componentCount" => 90
        }
      }

      case JSONBoundary.safe(%{"queryVersion" => 1, "presentation" => presentation}) do
        {:ok, payload} -> {:ok, payload}
        {:error, _reason} -> {:error, :application_surface_bounds_exceeded}
      end
    else
      :error -> {:error, :unsupported_application_surface_query}
      false -> {:error, :unsupported_application_surface_query}
      {:error, _reason} -> {:error, :unsupported_application_surface_query}
    end
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp mission_name(
         %Scope{mission: %{mission_id: mission_id, display_name: display_name}},
         mission_id
       ),
       do: display_name

  defp mission_name(%Scope{}, mission_id), do: mission_id
end
