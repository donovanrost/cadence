defmodule CadenceWeb.ConsolePaths do
  @moduledoc """
  Console URLs for legacy redirects (DECISIONS #79, docs/apogee/plans/legacy-deletion.md). Console
  paths carry the organization and mission slugs; legacy URLs carry ids, so the slugs are looked
  up from the signed-in organization. A mission that isn't the organization's (or doesn't exist),
  or an organization without a slug, falls back to `/console`. Query parameters pass through
  only when the caller keeps them.
  """

  alias Cadence.{Missions, Organizations}

  @doc "`/console/<org>/<mission><rest>`, or `/console`."
  @spec mission(binary() | nil, binary(), binary(), map()) :: binary()
  def mission(organization_id, mission_id, rest, query \\ %{})

  def mission(organization_id, mission_id, rest, query) when is_binary(organization_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id) do
      "/console/#{segment(organization.slug)}/#{segment(mission.slug)}" <> rest <> qs(query)
    else
      _other -> "/console"
    end
  end

  def mission(_organization_id, _mission_id, _rest, _query), do: "/console"

  @doc "`/console/<org><rest>`, or `/console`."
  @spec organization(binary() | nil, binary(), map()) :: binary()
  def organization(organization_id, rest, query \\ %{})

  def organization(organization_id, rest, query) when is_binary(organization_id) do
    case Organizations.fetch_organization(organization_id) do
      {:ok, %{slug: slug}} when is_binary(slug) ->
        "/console/#{segment(slug)}" <> rest <> qs(query)

      _other ->
        "/console"
    end
  end

  def organization(_organization_id, _rest, _query), do: "/console"

  @doc "An escaped path segment."
  @spec segment(binary()) :: binary()
  def segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @doc "`?a=1&b=2` from the kept, non-empty parameters, or empty."
  @spec qs(map()) :: binary()
  def qs(query) do
    case Enum.reject(query, fn {_key, value} -> value in [nil, ""] end) do
      [] -> ""
      kept -> "?" <> URI.encode_query(kept)
    end
  end
end
