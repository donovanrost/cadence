defmodule Cadence.GroundNetworks.EphemerisFindings do
  @moduledoc """
  Ephemeris problems grouped by cause (#972), from the same bound pairs and recorded outcomes as
  the providers read's `ephemeris` buckets (`EphemerisStates`), so they always agree and a stale
  row (its set, pinned version or ref no longer current) never raises one:

    * `norad_id_missing`: a lookup provider can't find the spacecraft, because its current element
      set carries no NORAD id. One group per provider.
    * `failed`: the latest upload of the current set failed and is retried with backoff. One
      group per provider; each spacecraft's own reason is on its member row.
    * `not_ready`: a routing rule binds the spacecraft to the provider, but no route is ready. One
      group per provider and refusal reason (a `ProviderScheduling` code).

  `groups/2` is one grouped query per mission; `members/4` pages a group's spacecraft by id. A
  group clears by itself once no pair is in it.
  """

  alias Cadence.GroundNetworks.EphemerisStates
  alias Cadence.Repo

  @causes ~w(norad_id_missing failed not_ready)
  @sample 10
  @max_limit 200

  @type group :: %{
          provider_id: binary(),
          cause: binary(),
          reason: binary() | nil,
          spacecraft_count: pos_integer(),
          spacecraft_ids: [binary()],
          since: DateTime.t() | nil,
          next_retry_at: DateTime.t() | nil
        }

  @doc "The causes, the `bucket` values a group comes from."
  @spec causes() :: [binary()]
  def causes, do: @causes

  @doc """
  The mission's groups (one query), ordered by provider, cause and reason. `spacecraft_ids` is a
  sample of at most #{@sample}, by id; `spacecraft_count` is the whole group. `since` is the
  earliest time a member's outcome was recorded, and `next_retry_at` the earliest retry
  (`failed` and `not_ready` only).
  """
  @spec groups(binary(), binary()) :: [group()]
  def groups(organization_id, mission_id) do
    sql =
      EphemerisStates.pairs_sql(:mission) <>
        """
        SELECT provider_id, bucket, #{reason_sql()} AS reason, count(*),
          (array_agg(spacecraft_id ORDER BY spacecraft_id))[1:#{@sample}],
          min(state_updated_at), min(state_next_retry_at)
        FROM pairs
        WHERE bucket = ANY($3::text[])
        GROUP BY 1, 2, 3
        ORDER BY 1, 2, 3
        """

    sql
    |> Repo.query!([organization_id, mission_id, @causes])
    |> Map.fetch!(:rows)
    |> Enum.map(fn [provider_id, cause, reason, count, ids, since, retry] ->
      %{
        provider_id: provider_id,
        cause: cause,
        reason: blank_to_nil(reason),
        spacecraft_count: count,
        spacecraft_ids: ids,
        since: utc(since),
        next_retry_at: utc(retry)
      }
    end)
  end

  @doc """
  One page of a group's spacecraft, by id: `{:ok, %{members, next_cursor}}`. `group` is
  `%{provider_id, cause, reason}` (`reason` only for `not_ready`); `opts`: `:after` (the last id of
  the page before) and `:limit` (1 to #{@max_limit}, default 50). Each member is `%{spacecraft_id,
  reason, attempts, next_retry_at, since}` as its recorded outcome holds them.
  """
  @spec members(binary(), binary(), map(), keyword()) ::
          {:ok, %{members: [map()], next_cursor: binary() | nil}} | {:error, :unknown_cause}
  def members(
        organization_id,
        mission_id,
        %{provider_id: provider_id, cause: cause} = group,
        opts
      )
      when cause in @causes do
    limit = opts |> Keyword.get(:limit, 50) |> max(1) |> min(@max_limit)

    sql =
      EphemerisStates.pairs_sql(:mission) <>
        """
        SELECT spacecraft_id, state_reason, state_attempts, state_next_retry_at, state_updated_at
        FROM pairs
        WHERE provider_id = $3 AND bucket = $4 AND #{reason_sql()} = $5
          AND spacecraft_id > $6
        ORDER BY spacecraft_id
        LIMIT $7
        """

    params = [
      organization_id,
      mission_id,
      provider_id,
      cause,
      if(cause == "not_ready", do: Map.get(group, :reason) || "", else: ""),
      Keyword.get(opts, :after) || "",
      limit + 1
    ]

    rows = sql |> Repo.query!(params) |> Map.fetch!(:rows)
    {page, rest} = Enum.split(rows, limit)

    members =
      Enum.map(page, fn [spacecraft_id, reason, attempts, retry, since] ->
        %{
          spacecraft_id: spacecraft_id,
          reason: reason,
          attempts: attempts,
          next_retry_at: utc(retry),
          since: utc(since)
        }
      end)

    next = if rest == [], do: nil, else: List.last(members).spacecraft_id
    {:ok, %{members: members, next_cursor: next}}
  end

  def members(_organization_id, _mission_id, _group, _opts), do: {:error, :unknown_cause}

  # A not_ready group is per refusal reason; failed and norad_id_missing groups are per provider.
  defp reason_sql,
    do: "CASE WHEN bucket = 'not_ready' THEN coalesce(state_reason, '') ELSE '' END"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(reason), do: reason

  defp utc(nil), do: nil
  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
