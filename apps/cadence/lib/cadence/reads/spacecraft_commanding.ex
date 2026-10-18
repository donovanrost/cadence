defmodule Cadence.Reads.SpacecraftCommanding do
  @moduledoc "Authorized pinned spacecraft interpretation and exact command target identities."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.{Ids, Missions, SourceEndpoints, SpacecraftStore, SpacecraftTypeStore}

  def load(scope, mission_id, spacecraft_id, params \\ %{})

  def load(
        %Scope{actor_kind: :user, user: %{user_id: user}} = scope,
        mission_id,
        spacecraft_id,
        params
      ) do
    with true <- is_binary(user) and scope.mission_id in [nil, mission_id],
         {:ok, _} <- Ids.path_segment(mission_id),
         {:ok, _} <- Ids.path_segment(spacecraft_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, craft} <-
           SpacecraftStore.fetch_spacecraft(scope.organization_id, mission_id, spacecraft_id),
         {:ok, query} <- admit_query(params) do
      endpoints = endpoints(scope.organization_id, mission_id, spacecraft_id, query)

      data = %{
        "version" => 1,
        "context" => %{
          "organizationId" => scope.organization_id,
          "missionId" => mission_id,
          "spacecraftId" => spacecraft_id
        },
        "mission_name" => mission.display_name,
        "spacecraft_name" => craft.display_name,
        "scid" => craft.scid,
        "profile" => profile(scope.organization_id, mission_id, craft),
        "query" => Map.put(query, "page", endpoints.page),
        "endpoints" => %{
          "page" => endpoints.page,
          "total_count" => endpoints.total_count,
          "items" =>
            Enum.map(
              endpoints.items,
              &%{"id" => &1.source_endpoint_id, "name" => &1.display_name, "scid" => &1.scid}
            )
        }
      }

      if byte_size(Jason.encode!(data)) <= 65_536, do: {:ok, data}, else: {:error, :unavailable}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def load(_, _, _, _), do: {:error, :unavailable}

  def admit_query(params) when is_map(params) and map_size(params) <= 2 do
    with true <-
           Enum.all?(params, fn {key, value} ->
             key in ["page", "query"] and query_text?(value)
           end),
         {page, ""} when page in 1..100_000 <- Integer.parse(Map.get(params, "page", "1")) do
      {:ok, %{"page" => page, "query" => String.trim(Map.get(params, "query", ""))}}
    else
      _ -> {:error, :invalid_commanding_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_commanding_query}

  defp query_text?(value),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) <= 240 and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)

  defp endpoints(org, mission, craft, query) do
    opts = [spacecraft_id: craft, page: query["page"], search: query["query"], page_size: 25]
    page = SourceEndpoints.list_source_endpoints_page(org, mission, opts)
    last = max(1, ceil(page.total_count / 25))

    if page.page > last,
      do:
        SourceEndpoints.list_source_endpoints_page(org, mission, Keyword.put(opts, :page, last)),
      else: page
  end

  defp profile(_org, _mission, %{spacecraft_type_id: nil, spacecraft_type_version: nil}) do
    profile_reference("unbound", nil, nil)
  end

  defp profile(org, mission, craft) do
    reference =
      profile_reference("unavailable", craft.spacecraft_type_id, craft.spacecraft_type_version)

    case fetch_profile(org, mission, craft) do
      {:ok, profile} ->
        Map.merge(reference, %{
          "status" => "ready",
          "name" => profile.display_name,
          "lifecycle" => to_string(profile.lifecycle_state),
          "uplink" => to_string(profile.uplink_protocol),
          "packet" => to_string(profile.packet_protocol)
        })

      _ ->
        reference
    end
  end

  defp fetch_profile(org, mission, %{spacecraft_type_id: id, spacecraft_type_version: version})
       when is_binary(id) and is_integer(version) and version > 0 do
    SpacecraftTypeStore.fetch_spacecraft_type_version(org, mission, id, version)
  end

  defp fetch_profile(_, _, _), do: {:error, :unavailable}

  defp profile_reference(status, id, version),
    do: %{
      "status" => status,
      "id" => id,
      "version" => version,
      "name" => nil,
      "lifecycle" => nil,
      "uplink" => nil,
      "packet" => nil
    }
end
