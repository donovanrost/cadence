defmodule CadenceWeb.Console.ProviderEphemerisController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/providers/:provider_id/ephemeris/spacecraft` (#972): one
  page of the spacecraft in a `provider_ephemeris` attention group, named with their SCIDs.
  Contract: docs/apogee/api/setup.md (Provider ephemeris spacecraft).
  """

  use CadenceWeb, :controller

  alias Cadence.GroundNetworks.{EphemerisFindings, EphemerisReasons, MissionProviders}
  alias Cadence.SpacecraftStore
  alias CadenceWeb.Console.Problem

  # todo(authz): reads are open to the mission's console members, like the providers read.
  def spacecraft(conn, %{"provider_id" => provider_id} = params) do
    with {:ok, cause} <- cause(params["cause"]),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, _provider} <-
           MissionProviders.fetch_provider(org(conn), mission(conn), provider_id),
         group = %{provider_id: provider_id, cause: cause, reason: blank(params["reason"])},
         {:ok, page} <-
           EphemerisFindings.members(org(conn), mission(conn), group,
             after: params["cursor"],
             limit: limit
           ),
         {:ok, craft} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(
             org(conn),
             mission(conn),
             Enum.map(page.members, & &1.spacecraft_id)
           ) do
      json(conn, %{
        data: Enum.map(page.members, &member(&1, cause, craft)),
        meta: %{next_cursor: page.next_cursor}
      })
    else
      {:error, {:invalid_param, field, reason}} ->
        Problem.respond(conn, :invalid_params, %{field: field, reason: reason})

      {:error, :mission_provider_not_found} ->
        Problem.respond(conn, :provider_not_found)

      {:error, reason} when is_atom(reason) ->
        Problem.respond(conn, reason)
    end
  end

  defp cause(cause) do
    if cause in EphemerisFindings.causes(),
      do: {:ok, cause},
      else: {:error, {:invalid_param, "cause", "must be norad_id_missing, failed or not_ready"}}
  end

  defp limit(nil), do: {:ok, 50}

  defp limit(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _other -> {:error, {:invalid_param, "limit", "must be 1 to 200"}}
    end
  end

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  # `detail` is the fixed sentence for the closed code (`EphemerisReasons`), never provider text.
  defp member(member, cause, craft) do
    spacecraft = Map.get(craft, member.spacecraft_id)

    %{
      spacecraft: %{
        id: member.spacecraft_id,
        name: spacecraft && spacecraft.display_name,
        scid: spacecraft && spacecraft.scid
      },
      reason: member.reason,
      detail: EphemerisReasons.detail(cause, member.reason),
      attempts: member.attempts,
      next_retry_at: member.next_retry_at,
      since: member.since
    }
  end

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
