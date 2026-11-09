defmodule Cadence.Contacts.PassResults.Queries do
  @moduledoc "Span queries over pass results for pass review (S9). Scoped by org and mission."

  import Ecto.Query

  alias Cadence.Contacts.PassResults.Row
  alias Cadence.Repo

  @max_limit 200

  @doc "Rows in `[from, to)` by planned AOS, filtered, newest first: `{rows, total, disputable}`."
  @spec rows(binary(), binary(), DateTime.t(), DateTime.t(), map()) ::
          {[Row.t()], non_neg_integer(), non_neg_integer()}
  def rows(organization_id, mission_id, from, to, filters) do
    query = filtered(span(organization_id, mission_id, from, to), filters)
    limit = filters |> Map.get(:limit, 50) |> min(@max_limit) |> max(1)
    offset = Map.get(filters, :offset, 0)

    rows =
      query
      |> order_by([r], desc: r.planned_aos, asc: r.provider_reservation_id)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    %{total: total, disputable: disputable} =
      query
      |> select([r], %{
        total: count(r.provider_reservation_id),
        disputable: filter(count(r.provider_reservation_id), r.disputable)
      })
      |> Repo.one()

    {rows, total, disputable}
  end

  @doc "Counts by outcome, by owner, by station, by cause and by UTC day, plus booking plans."
  @spec aggregate(binary(), binary(), DateTime.t(), DateTime.t(), binary() | nil) :: map()
  def aggregate(organization_id, mission_id, from, to, plan) do
    base = filtered(span(organization_id, mission_id, from, to), %{plan: plan})

    %{
      outcomes: grouped(base, [:outcome]),
      owners: grouped(base, [:outcome, :owner]),
      stations: stations(base),
      causes: grouped(base, [:cause, :cause_source, :owner, :outcome]),
      days: days(base),
      plans:
        base
        |> where([r], not is_nil(r.contact_plan_id))
        |> distinct(true)
        |> select([r], %{id: r.contact_plan_id, version: r.contact_plan_version})
        |> order_by([r], asc: r.contact_plan_id, asc: r.contact_plan_version)
        |> Repo.all(),
      provider_ids: base |> distinct(true) |> select([r], r.provider_id) |> Repo.all(),
      # Span totals for "Downlink: received vs provider-reported". The counts say how many passes
      # contributed each figure, since unknown volumes are null, not 0.
      volume:
        base
        |> select([r], %{
          provider_bytes: sum(r.provider_bytes),
          provider_frames: sum(r.provider_frames),
          received_bytes: sum(r.received_bytes),
          received_frames: sum(r.received_frames),
          provider_reported_passes: count(r.provider_bytes),
          received_known_passes: count(r.received_bytes)
        })
        |> Repo.one()
    }
  end

  defp span(organization_id, mission_id, from, to) do
    from(r in Row,
      where:
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.planned_aos >= ^from and r.planned_aos < ^to
    )
  end

  defp filtered(query, filters) do
    Enum.reduce(filters, query, fn
      {:outcome, [_ | _] = outcomes}, q ->
        where(q, [r], r.outcome in ^outcomes)

      {:station, station}, q when is_binary(station) ->
        where(q, [r], r.ground_station_ref == ^station)

      {:spacecraft_id, id}, q when is_binary(id) ->
        where(q, [r], r.spacecraft_id == ^id)

      {:plan, plan}, q when is_binary(plan) ->
        where(q, [r], r.contact_plan_id == ^plan)

      _other, q ->
        q
    end)
  end

  defp grouped(query, fields) do
    query
    |> group_by([r], ^fields)
    |> select([r], {map(r, ^fields), count(r.provider_reservation_id)})
    |> Repo.all()
  end

  defp stations(query) do
    query
    |> group_by([r], [r.ground_station_ref, r.provider_id, r.outcome])
    |> select([r], %{
      ground_station_ref: r.ground_station_ref,
      provider_id: r.provider_id,
      outcome: r.outcome,
      count: count(r.provider_reservation_id),
      planned_seconds: sum(r.planned_seconds),
      flown_seconds: sum(r.flown_seconds)
    })
    |> Repo.all()
  end

  defp days(query) do
    query
    |> group_by([r], [
      fragment("date_trunc('day', ?)", r.planned_aos),
      r.outcome,
      r.cause,
      r.ground_station_ref
    ])
    |> select([r], %{
      day: fragment("date_trunc('day', ?)::date", r.planned_aos),
      outcome: r.outcome,
      cause: r.cause,
      station: r.ground_station_ref,
      count: count(r.provider_reservation_id)
    })
    |> Repo.all()
  end
end
