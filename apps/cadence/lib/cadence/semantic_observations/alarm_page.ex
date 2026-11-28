defmodule Cadence.SemanticObservations.AlarmPage do
  @moduledoc """
  The alarm list's database reads (#794, moved from the ground limit states to the runtime's
  `semantic_latest_alarm_states`, #451 T3c): the filters, the sort and the page in SQL, the counts
  over the same `WHERE`. Nothing here loads the mission's alarms: a page costs the page, not the
  fleet.

  The order: level (critical, then caution, then the rest), newest `receipt_time` first,
  spacecraft id, parameter id; the keyset cursor is the last row's sort key (`key/1`). A state is
  written when a parameter changes state, so `receipt_time` is when it entered the one it is in.
  The levels are `SemanticRuntime.AlarmLevel`'s, never a copy of its table.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.SemanticRuntime.AlarmLevel

  # 0 critical, 1 caution, 2 anything else (normal, disabled, unknown).
  defmacrop rank(state, critical, caution) do
    quote do
      fragment(
        "(CASE WHEN ? = ANY(?) THEN 0 WHEN ? = ANY(?) THEN 1 ELSE 2 END)",
        unquote(state),
        unquote(critical),
        unquote(state),
        unquote(caution)
      )
    end
  end

  @type filters :: map()
  @type key :: {non_neg_integer(), integer(), binary(), binary()}

  @doc "The sort key of a row: the keyset cursor's content."
  @spec key(struct()) :: key()
  def key(%LatestAlarmStateRow{} = row) do
    {rank_of(row.effective_state), -DateTime.to_unix(row.receipt_time, :microsecond),
     row.spacecraft_id || "", row.parameter_id}
  end

  @doc "The rank of a state: 0 critical, 1 caution, 2 the rest."
  @spec rank_of(binary()) :: 0 | 1 | 2
  def rank_of(state) do
    case AlarmLevel.level(state) do
      :critical -> 0
      :caution -> 1
      _other -> 2
    end
  end

  @doc """
  The rows after `after_key` (nil: from the start) matching `filters`, in order, at most
  `limit + 1` (the extra row says whether there is a next page).
  """
  @spec rows(binary(), binary(), filters(), key() | nil, pos_integer()) :: [struct()]
  def rows(organization_id, mission_id, filters, after_key, limit) do
    critical = AlarmLevel.states_of(:critical)
    caution = AlarmLevel.states_of(:caution)

    organization_id
    |> scope(mission_id, filters)
    |> after_key(after_key, critical, caution)
    |> order_by([r],
      asc: rank(r.effective_state, ^critical, ^caution),
      desc: r.receipt_time,
      asc: fragment("coalesce(?, '')", r.spacecraft_id),
      asc: r.parameter_id
    )
    |> limit(^(limit + 1))
    |> Repo.all()
  end

  @doc "How many rows match `filters` (the same `WHERE` as the page, whatever the page)."
  @spec count(binary(), binary(), filters()) :: non_neg_integer()
  def count(organization_id, mission_id, filters) do
    organization_id |> scope(mission_id, filters) |> Repo.aggregate(:count)
  end

  @doc """
  The mission's totals, whatever the filters: active alarms by level and the latest transition's
  receipt time.
  """
  @spec summary(binary(), binary()) :: %{
          active: non_neg_integer(),
          critical: non_neg_integer(),
          caution: non_neg_integer(),
          latest_transition_at: DateTime.t() | nil
        }
  def summary(organization_id, mission_id) do
    critical = AlarmLevel.states_of(:critical)
    caution = AlarmLevel.states_of(:caution)

    from(r in LatestAlarmStateRow,
      where: r.mission_id == ^mission_id and r.organization_id == ^organization_id,
      select: %{
        active: filter(count(r.id), r.effective_state in ^(critical ++ caution)),
        critical: filter(count(r.id), r.effective_state in ^critical),
        caution: filter(count(r.id), r.effective_state in ^caution),
        latest_transition_at: max(r.receipt_time)
      }
    )
    |> Repo.one()
  end

  defp scope(organization_id, mission_id, filters) do
    from(r in LatestAlarmStateRow,
      where: r.mission_id == ^mission_id and r.organization_id == ^organization_id
    )
    |> state(filters[:state])
    |> severity(filters[:severity])
    |> exact(filters[:spacecraft_id])
    |> parameters(filters[:parameter_ids])
    |> in_spacecraft(filters[:spacecraft_ids])
    |> not_spacecraft(filters[:exclude_spacecraft_id])
    |> matching(filters[:query], filters[:query_parameter_ids])
  end

  defp state(query, "nominal"),
    do: where(query, [r], r.effective_state not in ^AlarmLevel.alarm_states_text())

  defp state(query, "all"), do: query

  defp state(query, _active),
    do: where(query, [r], r.effective_state in ^AlarmLevel.alarm_states_text())

  defp severity(query, "critical"),
    do: where(query, [r], r.effective_state in ^AlarmLevel.states_of(:critical))

  defp severity(query, "caution"),
    do: where(query, [r], r.effective_state in ^AlarmLevel.states_of(:caution))

  defp severity(query, _any), do: query

  defp exact(query, value) when value in [nil, "", "all"], do: query
  defp exact(query, value), do: where(query, [r], r.spacecraft_id == ^value)

  # The parameters of the point asked for; nil does not restrict.
  defp parameters(query, nil), do: query
  defp parameters(query, ids) when is_list(ids), do: where(query, [r], r.parameter_id in ^ids)

  # A list (possibly empty) restricts to those spacecraft; nil does not.
  defp in_spacecraft(query, nil), do: query
  defp in_spacecraft(query, ids) when is_list(ids), do: where(query, [r], r.spacecraft_id in ^ids)

  defp not_spacecraft(query, value) when value in [nil, ""], do: query

  defp not_spacecraft(query, id),
    do: where(query, [r], is_nil(r.spacecraft_id) or r.spacecraft_id != ^id)

  # A substring of the parameter id, or one of the parameters whose point matched by name.
  defp matching(query, value, _ids) when value in [nil, ""], do: query

  defp matching(query, value, ids) do
    needle = String.downcase(value)

    where(
      query,
      [r],
      fragment("strpos(lower(?), ?) > 0", r.parameter_id, ^needle) or
        r.parameter_id in ^List.wrap(ids)
    )
  end

  # The rows strictly after the key in (rank asc, receipt_time desc, spacecraft asc, parameter asc).
  defp after_key(query, nil, _critical, _caution), do: query

  defp after_key(query, {severity, negative_micros, spacecraft, parameter}, critical, caution) do
    at = DateTime.from_unix!(-negative_micros, :microsecond)

    where(
      query,
      [r],
      rank(r.effective_state, ^critical, ^caution) > ^severity or
        (rank(r.effective_state, ^critical, ^caution) == ^severity and r.receipt_time < ^at) or
        (rank(r.effective_state, ^critical, ^caution) == ^severity and r.receipt_time == ^at and
           fragment(
             "(coalesce(?, ''), ?) > (?, ?)",
             r.spacecraft_id,
             r.parameter_id,
             ^spacecraft,
             ^parameter
           ))
    )
  end
end
