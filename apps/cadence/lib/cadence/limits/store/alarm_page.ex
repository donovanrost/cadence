defmodule Cadence.Limits.Store.AlarmPage do
  @moduledoc """
  The alarm list's database reads (#794): the filters, the sort and the page in SQL over
  `telemetry_latest_limit_states`, the counts over the same `WHERE`, and the crossing time of a
  page's alarms in one statement. Nothing here loads the mission's alarms: a page costs the page,
  not the fleet.

  The order is `Cadence.Reads.Alarms.sort_key/1` expressed in SQL: severity rank (red, yellow,
  blue, green), newest `receipt_time` first, spacecraft id, point id. The active set has a
  partial index in exactly that order, so an active page is an index range, and the keyset cursor
  (the last row's sort key) continues where the page stopped.
  """

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.LatestStateRow
  alias Cadence.Repo

  # The severity rank of a state; the partial index is on exactly this expression.
  defmacrop rank(state) do
    quote do
      fragment(
        "(CASE ? WHEN 'red' THEN 0 WHEN 'yellow' THEN 1 WHEN 'blue' THEN 2 ELSE 3 END)",
        unquote(state)
      )
    end
  end

  @type filters :: map()
  @type key :: {non_neg_integer(), integer(), binary(), binary()}

  @doc """
  The rows after `after_key` (nil: from the start) matching `filters`, in order, at most
  `limit + 1` (the extra row says whether there is a next page).
  """
  @spec rows(binary(), binary(), filters(), key() | nil, pos_integer()) :: [Event.t()]
  def rows(organization_id, mission_id, filters, after_key, limit) do
    organization_id
    |> scope(mission_id, filters)
    |> after_key(after_key)
    |> order_by([r],
      asc: rank(r.normalized_state),
      desc: r.receipt_time,
      asc: fragment("coalesce(?, '')", r.spacecraft_id),
      asc: r.point_id
    )
    |> limit(^(limit + 1))
    |> Repo.all()
    |> Enum.map(&LatestStateRow.to_domain/1)
  end

  @doc "How many rows match `filters` (the same `WHERE` as the page, whatever the page)."
  @spec count(binary(), binary(), filters()) :: non_neg_integer()
  def count(organization_id, mission_id, filters) do
    organization_id |> scope(mission_id, filters) |> Repo.aggregate(:count)
  end

  @doc """
  The mission's totals, whatever the filters: active alarms by severity and the latest
  transition's receipt time.
  """
  @spec summary(binary(), binary()) :: map()
  def summary(organization_id, mission_id) do
    from(r in LatestStateRow,
      where: r.mission_id == ^mission_id and r.organization_id == ^organization_id,
      select: %{
        active: filter(count(r.id), r.violation),
        critical: filter(count(r.id), r.violation and r.normalized_state == "red"),
        warning: filter(count(r.id), r.violation and r.normalized_state == "yellow"),
        info: filter(count(r.id), r.violation and r.normalized_state == "blue"),
        latest_transition_at: max(r.receipt_time)
      }
    )
    |> Repo.one()
  end

  @doc """
  When each given alarm entered its current state: `%{{spacecraft_id, point_id} => DateTime}`.
  `alarms` are `{spacecraft_id, point_id, normalized_state}`. One statement for the page (and a
  second only if the page has mission-scope alarms, which have no spacecraft): the first event
  after the newest event of another state, among the newest 200 of that (spacecraft, point),
  by generation time (receipt time without one).
  """
  @spec crossed_at(binary(), [{binary() | nil, binary(), binary()}]) :: %{
          {binary() | nil, binary()} => DateTime.t()
        }
  def crossed_at(_mission_id, []), do: %{}

  def crossed_at(mission_id, alarms) do
    {mission, craft} =
      Enum.split_with(alarms, fn {spacecraft, _point, _state} -> is_nil(spacecraft) end)

    Map.merge(
      crossed(mission_id, craft, "e.spacecraft_id = p.sc"),
      crossed(mission_id, mission, "e.spacecraft_id IS NULL")
    )
  end

  defp crossed(_mission_id, [], _match), do: %{}

  defp crossed(mission_id, alarms, match) do
    {spacecraft, points, states} =
      Enum.reduce(alarms, {[], [], []}, fn {sc, point, state}, {a, b, c} ->
        {[sc | a], [point | b], [state | c]}
      end)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT p.sc, p.pt, r.crossed
        FROM unnest($2::text[], $3::text[], $4::text[]) AS p(sc, pt, st)
        CROSS JOIN LATERAL (
          WITH w AS (
            SELECT e.receipt_time, e.generation_time, e.normalized_state
            FROM telemetry_limit_events e
            WHERE e.mission_id = $1 AND #{match} AND e.point_id = p.pt
            ORDER BY e.receipt_time DESC, e.limit_event_id DESC
            LIMIT 200)
          SELECT coalesce(w.generation_time, w.receipt_time) AS crossed
          FROM w
          WHERE w.receipt_time > coalesce(
            (SELECT max(x.receipt_time) FROM w x WHERE x.normalized_state <> p.st),
            '-infinity'::timestamp)
          ORDER BY w.receipt_time ASC
          LIMIT 1) r
        """,
        [mission_id, spacecraft, points, states]
      )

    Map.new(rows, fn [sc, point, crossed] ->
      {{sc, point}, DateTime.from_naive!(crossed, "Etc/UTC")}
    end)
  end

  defp scope(organization_id, mission_id, filters) do
    from(r in LatestStateRow,
      where: r.mission_id == ^mission_id and r.organization_id == ^organization_id
    )
    |> state(filters[:state])
    |> severity(filters[:severity])
    |> exact(:spacecraft_id, filters[:spacecraft_id])
    |> exact(:point_id, filters[:point_id])
    |> in_spacecraft(filters[:spacecraft_ids])
    |> not_spacecraft(filters[:exclude_spacecraft_id])
    |> matching(filters[:query])
  end

  defp state(query, "nominal"), do: where(query, [r], not r.violation)
  defp state(query, "all"), do: query
  defp state(query, _active), do: where(query, [r], r.violation)

  # The console's `warning` is the projection's yellow.
  defp severity(query, "critical"), do: where(query, [r], r.normalized_state == "red")
  defp severity(query, "warning"), do: where(query, [r], r.normalized_state == "yellow")
  defp severity(query, _any), do: query

  defp exact(query, _field, value) when value in [nil, "", "all"], do: query
  defp exact(query, :spacecraft_id, value), do: where(query, [r], r.spacecraft_id == ^value)
  defp exact(query, :point_id, value), do: where(query, [r], r.point_id == ^value)

  # A list (possibly empty) restricts to those spacecraft; nil does not.
  defp in_spacecraft(query, nil), do: query
  defp in_spacecraft(query, ids) when is_list(ids), do: where(query, [r], r.spacecraft_id in ^ids)

  defp not_spacecraft(query, value) when value in [nil, ""], do: query

  defp not_spacecraft(query, id),
    do: where(query, [r], is_nil(r.spacecraft_id) or r.spacecraft_id != ^id)

  # A substring of the point's id, name or limit set (its subsystem is a prefix of its id).
  defp matching(query, value) when value in [nil, ""], do: query

  defp matching(query, value) do
    needle = String.downcase(value)

    where(
      query,
      [r],
      fragment("strpos(lower(?), ?) > 0", r.point_id, ^needle) or
        fragment("strpos(lower(?), ?) > 0", r.point_name, ^needle) or
        fragment("strpos(lower(?), ?) > 0", r.limit_set_name, ^needle)
    )
  end

  # The rows strictly after the key in (rank asc, receipt_time desc, spacecraft asc, point asc).
  defp after_key(query, nil), do: query

  defp after_key(query, {severity, negative_micros, spacecraft, point}) do
    at = DateTime.from_unix!(-negative_micros, :microsecond)

    where(
      query,
      [r],
      rank(r.normalized_state) > ^severity or
        (rank(r.normalized_state) == ^severity and r.receipt_time < ^at) or
        (rank(r.normalized_state) == ^severity and r.receipt_time == ^at and
           fragment(
             "(coalesce(?, ''), ?) > (?, ?)",
             r.spacecraft_id,
             r.point_id,
             ^spacecraft,
             ^point
           ))
    )
  end
end
