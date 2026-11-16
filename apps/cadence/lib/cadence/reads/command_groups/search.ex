defmodule Cadence.Reads.CommandGroups.Search do
  @moduledoc """
  U69 A5a/b/c (fe-ops, parity ops (C)): the Commands list searched, filtered and paged, newest
  first (`requested_at`, then id), with an opaque cursor.

    * `q`: case-insensitive substring of the title, log entry, group id, operation id, or a
      stacked command's id or name.
    * `target`: groups with that spacecraft among their targets.
    * `states`, `mine`, `awaiting_me`: in SQL, so a page is exact.
    * `stages`: groups where ANY target is at one of `release_failed | verify_failed |
      indeterminate | in_flight | queued_for_contact` (`in_flight` = `radiating` or `executed`).
      A target's stage depends on its members' order, so SQL keeps the groups with a member in a
      related state and the read's own progress (`CommandGroups.rows/4`) decides: the filter
      and the progress badge always agree. Rounds continue until the page is full, at most
      #{10} rounds; `next_cursor` continues where reading stopped.
  """

  import Ecto.Query

  alias Cadence.Commanding.Groups.CommandGroupRow
  alias Cadence.Reads.CommandGroups
  alias Cadence.Repo

  @rounds 10
  @in_flight [:radiating, :executed]

  @stages ~w(release_failed verify_failed indeterminate in_flight queued_for_contact)

  @spec stages() :: [binary()]
  def stages, do: @stages

  def page(org, mission, viewer_id, opts) do
    with {:ok, cursor} <- decode(opts[:cursor]) do
      query = base(org, mission, viewer_id, opts)
      limit = Keyword.get(opts, :limit, 100)

      ctx = %{org: org, mission: mission, viewer: viewer_id, query: query, stages: opts[:stages]}
      {rows, next} = collect(ctx, cursor, limit, [], @rounds)
      {:ok, %{groups: rows, next_cursor: encode(next)}}
    end
  end

  defp collect(_ctx, cursor, remaining, acc, rounds) when remaining <= 0 or rounds <= 0,
    do: {acc, cursor}

  defp collect(ctx, cursor, remaining, acc, rounds) do
    batch =
      ctx.query
      |> after_cursor(cursor)
      |> order_by([g], desc: g.requested_at, desc: g.command_group_id)
      |> limit(^(remaining + 1))
      |> Repo.all()

    {batch, more?} = {Enum.take(batch, remaining), length(batch) > remaining}
    groups = Enum.map(batch, &CommandGroupRow.to_domain/1)

    kept =
      ctx.org
      |> CommandGroups.rows(ctx.mission, groups, ctx.viewer)
      |> Enum.filter(&at_stage?(&1, ctx.stages))

    last = List.last(batch)
    next = if more? and last, do: {last.requested_at, last.command_group_id}

    cond do
      is_nil(next) -> {acc ++ kept, nil}
      is_nil(ctx.stages) -> {acc ++ kept, next}
      true -> collect(ctx, next, remaining - length(kept), acc ++ kept, rounds - 1)
    end
  end

  defp at_stage?(_row, nil), do: true

  defp at_stage?(%{progress: progress}, stages) when is_map(progress) do
    Enum.any?(Map.keys(progress), fn stage ->
      to_string(stage) in stages or ("in_flight" in stages and stage in @in_flight)
    end)
  end

  defp at_stage?(_row, _stages), do: false

  defp base(org, mission, viewer, opts) do
    CommandGroupRow
    |> where([g], g.organization_id == ^org and g.mission_id == ^mission)
    |> states(opts[:states])
    |> text(opts[:q])
    |> target(opts[:target])
    |> mine(opts[:mine], viewer)
    |> awaiting(opts[:awaiting_me], viewer)
    |> related(opts[:stages])
  end

  defp states(query, nil), do: query
  defp states(query, states), do: where(query, [g], g.state in ^Enum.map(states, &to_string/1))

  defp text(query, nil), do: query

  defp text(query, q) do
    like = "%" <> String.replace(q, ~r/([\\%_])/, "\\\\\\1") <> "%"

    where(
      query,
      [g],
      ilike(g.title, ^like) or ilike(g.log_entry, ^like) or ilike(g.command_group_id, ^like) or
        ilike(g.operation_id, ^like) or
        fragment(
          "EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(?->'value') = 'array' THEN ?->'value' ELSE '[]'::jsonb END) c WHERE c->>'command_id' ILIKE ? OR c->>'name' ILIKE ?)",
          g.commands_document,
          g.commands_document,
          ^like,
          ^like
        )
    )
  end

  defp target(query, nil), do: query

  defp target(query, spacecraft_id) do
    # Postgrex encodes the term as jsonb itself (a pre-encoded string would be encoded twice).
    contains = [%{"spacecraft_id" => spacecraft_id}]
    where(query, [g], fragment("(?->'value') @> ?::jsonb", g.targets_document, ^contains))
  end

  defp mine(query, true, viewer) when is_binary(viewer),
    do: where(query, [g], fragment("?->'value'->>'user_id'", g.requested_by_document) == ^viewer)

  defp mine(query, true, _no_viewer), do: where(query, false)
  defp mine(query, _all, _viewer), do: query

  # CommandGroups.awaiting?/2 in SQL: pending, not mine, and I'm the named approver or none was.
  defp awaiting(query, true, viewer) when is_binary(viewer) do
    where(
      query,
      [g],
      g.state == "approval_pending" and
        fragment("COALESCE(?->'value'->>'user_id', '')", g.requested_by_document) != ^viewer and
        (is_nil(g.requested_approver_user_id) or g.requested_approver_user_id == ^viewer)
    )
  end

  defp awaiting(query, true, _no_viewer), do: where(query, false)
  defp awaiting(query, _all, _viewer), do: query

  # Stage filters apply to delivery, so only queued groups; SQL keeps the groups with a member
  # in a state that can put its target at the stage (a superset; the progress decides).
  defp related(query, nil), do: query

  defp related(query, stages) do
    any = Enum.reduce(stages, dynamic(false), &dynamic([g], ^&2 or ^related_clause(&1)))
    query |> where([g], g.state == "queued") |> where(^any)
  end

  defp related_clause("release_failed"), do: attempt_in(["release_failed"])
  defp related_clause("indeterminate"), do: attempt_in(["release_uncertain"])
  defp related_clause("in_flight"), do: attempt_in(["release_pending", "released"])

  defp related_clause("verify_failed"),
    do:
      dynamic(
        [g],
        fragment(
          "EXISTS (SELECT 1 FROM command_requests r WHERE r.organization_id = ? AND r.mission_id = ? AND r.command_group_id = ? AND r.verification_state IN ('failed', 'timed_out'))",
          g.organization_id,
          g.mission_id,
          g.command_group_id
        )
      )

  defp related_clause("queued_for_contact"),
    do:
      dynamic(
        [g],
        fragment(
          "EXISTS (SELECT 1 FROM command_requests r WHERE r.organization_id = ? AND r.mission_id = ? AND r.command_group_id = ? AND r.lifecycle_state = 'queued')",
          g.organization_id,
          g.mission_id,
          g.command_group_id
        )
      )

  defp attempt_in(states),
    do:
      dynamic(
        [g],
        fragment(
          "EXISTS (SELECT 1 FROM command_requests r JOIN command_release_attempts a ON a.organization_id = r.organization_id AND a.mission_id = r.mission_id AND a.command_request_id = r.command_request_id WHERE r.organization_id = ? AND r.mission_id = ? AND r.command_group_id = ? AND a.lifecycle_state = ANY(?))",
          g.organization_id,
          g.mission_id,
          g.command_group_id,
          type(^states, {:array, :string})
        )
      )

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, {at, id}),
    do:
      where(query, [g], fragment("(?, ?) < (?, ?)", g.requested_at, g.command_group_id, ^at, ^id))

  defp encode(nil), do: nil

  defp encode({%DateTime{} = at, id}),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> "|" <> id, padding: false)

  defp decode(nil), do: {:ok, nil}

  defp decode(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [iso, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, 0} <- DateTime.from_iso8601(iso) do
      {:ok, {at, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end
end
