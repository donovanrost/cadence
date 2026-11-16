defmodule Cadence.Reads.ConsoleSampleLinks do
  @moduledoc """
  Console links to a telemetry sample (§11c(D) D2), the same link the console's AlarmProvenance
  builds: `/console/<org>/<mission>/fleet/<scid>/telemetry?points=<point>&focus=<point>&at=<time>`,
  `at` being the sample's generation time, else its receipt time (the alarm trigger's rule,
  `AlarmEpisodes.Triggers`), since Investigate's plot positions on generation time.

  Falls back to `/console/<org>/<mission>/telemetry?p=<point>` when the row has no spacecraft or
  the spacecraft no SCID, and to `/console` when the slugs don't resolve. Computed at read time
  from the current slugs (never stored), so a rename can't leave a stale link.
  """

  alias Cadence.{Missions, Organizations, SpacecraftStore}

  @type context :: %{base: binary() | nil, scids: %{optional(binary()) => integer()}}

  @doc "The mission's console base path and its spacecraft SCIDs, read once per page."
  @spec context(binary(), binary()) :: context()
  def context(organization_id, mission_id) do
    %{base: base(organization_id, mission_id), scids: scids(organization_id, mission_id)}
  end

  @doc "The link for one sample of `point_id` on `spacecraft_id` (nil for a mission state)."
  @typedoc "A time as the row already shows it (an ISO string), or a DateTime."
  @type at :: binary() | DateTime.t() | nil

  @spec href(context(), binary() | nil, binary(), at(), at()) :: binary()
  def href(%{base: nil}, _spacecraft_id, _point_id, _generated, _received), do: "/console"

  def href(%{base: base, scids: scids}, spacecraft_id, point_id, generated, received) do
    case Map.get(scids, spacecraft_id) do
      scid when is_integer(scid) ->
        query = put_at(%{"points" => point_id, "focus" => point_id}, present(generated, received))
        base <> "/fleet/#{scid}/telemetry?" <> URI.encode_query(query)

      nil ->
        base <> "/telemetry?" <> URI.encode_query(%{"p" => point_id})
    end
  end

  # A string is used as is, so `at` is byte-equal to the row's own time field (fe-ops' reader).
  defp put_at(query, at) when is_binary(at) and at != "", do: Map.put(query, "at", at)

  defp put_at(query, %DateTime{} = at),
    do: Map.put(query, "at", DateTime.to_iso8601(at))

  defp put_at(query, _none), do: query

  defp present(generated, received) when generated in [nil, ""], do: received
  defp present(generated, _received), do: generated

  defp base(organization_id, mission_id) do
    with {:ok, %{slug: org_slug}} when is_binary(org_slug) <-
           Organizations.fetch_organization(organization_id),
         {:ok, %{slug: mission_slug}} when is_binary(mission_slug) <-
           Missions.fetch_mission(organization_id, mission_id) do
      "/console/#{segment(org_slug)}/#{segment(mission_slug)}"
    else
      _unresolved -> nil
    end
  end

  defp scids(organization_id, mission_id) do
    organization_id
    |> SpacecraftStore.list_spacecraft(mission_id)
    |> Enum.filter(&is_integer(&1.scid))
    |> Map.new(&{&1.spacecraft_id, &1.scid})
  end

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
