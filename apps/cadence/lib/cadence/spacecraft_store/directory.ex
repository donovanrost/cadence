defmodule Cadence.SpacecraftStore.Directory do
  @moduledoc """
  The Setup directory's queries (#796): a page of a mission's active spacecraft by name then id,
  and the mission-wide counts its subtitle reads, each in one query. Nothing here loads the fleet.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore.SpacecraftRow

  @doc """
  The active spacecraft after `after_key` (`{name, id}` or nil), at most `limit`, by name then id.
  `filter` is `%{text: binary() | nil, profile_ids: [binary()]}`: a craft matches when its name
  contains the text (case-insensitive), its SCID starts with it, or its profile is one of
  `profile_ids`.
  """
  @spec page(binary(), binary(), {binary(), binary()} | nil, pos_integer(), map()) ::
          [Spacecraft.t()]
  def page(organization_id, mission_id, after_key, limit, filter) do
    organization_id
    |> active(mission_id)
    |> matching(filter)
    |> after_name(after_key)
    |> order_by([row], asc: row.display_name, asc: row.spacecraft_id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&SpacecraftRow.to_domain/1)
  end

  @doc """
  The mission's counts: `total`, `profiles` (distinct profiles bound), `without_profile`,
  `without_scid`, `without_routing_rule` (not among `routed_ids`, the craft with an active, enabled
  rule) and `heard` (among `heard_ids`). Both lists are the ids another source knows; the match
  is against this mission's active craft only.
  """
  @spec counts(binary(), binary(), [binary()], [binary()]) :: %{atom() => non_neg_integer()}
  def counts(organization_id, mission_id, heard_ids, routed_ids) do
    organization_id
    |> active(mission_id)
    |> select([row], %{
      total: count(row.spacecraft_id),
      profiles: count(row.spacecraft_type_id, :distinct),
      without_profile: filter(count(row.spacecraft_id), is_nil(row.spacecraft_type_id)),
      without_scid: filter(count(row.spacecraft_id), is_nil(row.scid)),
      without_routing_rule:
        filter(count(row.spacecraft_id), row.spacecraft_id not in ^routed_ids),
      heard: filter(count(row.spacecraft_id), row.spacecraft_id in ^heard_ids)
    })
    |> Repo.one()
  end

  defp active(organization_id, mission_id) do
    from(row in SpacecraftRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.lifecycle_state == "active"
    )
  end

  defp after_name(query, nil), do: query

  defp after_name(query, {name, id}),
    do:
      where(
        query,
        [row],
        row.display_name > ^name or (row.display_name == ^name and row.spacecraft_id > ^id)
      )

  defp matching(query, %{text: text} = filter) when is_binary(text) and text != "" do
    like = "%" <> escape_like(text) <> "%"
    scid_prefix = escape_like(text) <> "%"
    profile_ids = Map.get(filter, :profile_ids, [])

    where(
      query,
      [row],
      ilike(row.display_name, ^like) or
        fragment("?::text LIKE ?", row.scid, ^scid_prefix) or
        row.spacecraft_type_id in ^profile_ids
    )
  end

  defp matching(query, _filter), do: query

  defp escape_like(text), do: String.replace(text, ["\\", "%", "_"], &("\\" <> &1))
end
