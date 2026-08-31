defmodule Cadence.Applications.LegacyCommsOverview.QueryProvider do
  @moduledoc "Application-owned provider for the compatibility overview query."

  @behaviour Cadence.Applications.HostQueryProvider

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.ApplicationSurfaces.Comms

  @query_id "cadence.comms.overview"

  @impl true
  def application_key, do: "comms_overview"

  @impl true
  def query_id, do: @query_id

  @impl true
  def query(
        %Scope{} = scope,
        %{
          host_context: %HostContext{placement: :mission},
          mission: %{
            mission_id: mission_id,
            organization_id: organization_id,
            display_name: display_name
          }
        },
        params,
        @query_id
      )
      when is_map(params) do
    with :ok <-
           Policy.authorize(scope, :read_legacy_application, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         :ok <- validate_identity(params),
         :ok <- validate_query_version(params),
         {:ok, presentation} <-
           Comms.overview_presentation(scope, %{
             mission_id: mission_id,
             organization_id: organization_id,
             display_name: display_name
           }) do
      {:ok, %{"queryVersion" => 1, "presentation" => presentation}}
    end
  end

  def query(%Scope{}, %{}, _params, _query_id), do: {:error, :unsupported_application_query}

  def query(%Scope{}, _route_context, _params, _query_id),
    do: {:error, :unsupported_application_query}

  defp validate_identity(params) do
    identity = Map.take(params, ~w(applicationKey applicationVersion surfaceId surfaceVersion))

    case identity do
      %{} when map_size(identity) == 0 ->
        :ok

      %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1
      } ->
        :ok

      _invalid ->
        {:error, :unsupported_application_query}
    end
  end

  defp validate_query_version(params) do
    case {Map.get(params, "queryVersion"), Map.get(params, "version")} do
      {nil, 1} -> :ok
      {1, nil} -> :ok
      {1, 1} -> :ok
      _invalid -> {:error, :unsupported_application_query}
    end
  end
end
