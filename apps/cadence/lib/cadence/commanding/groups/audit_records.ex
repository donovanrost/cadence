defmodule Cadence.Commanding.Groups.AuditRecords do
  @moduledoc """
  The commanding records the organization audit reads (director 11-15, ux U59). Nothing is
  written here: every entry comes from a record commanding already keeps.

    * `group_events`: a group's decisions from `command_group_events` (submitted, GO, GO with
      exclusions, NO-GO, sent back, aborted, released on a contact, HOLD acknowledged, a
      member canceled by an operator), each with its group's summary fields.
    * `group_cancels`: Cadence's own cancels of group members (expiry, fail-closed, a catalog
      change), folded to one row per group and reason, from each request's
      `metadata["cancellation"]`.
    * `requests`, `approvals`, `cancels`: standalone requests (no group), their approval
      decisions and their cancels (operator or Cadence), one row each.

  Each query is bounded by the page's window (`from`/`to`) and a cap, so a group of thousands of
  members gives a handful of rows, never one per member.
  """

  import Ecto.Query

  alias Cadence.Commanding.{CommandApprovalRow, CommandRequestRow}
  alias Cadence.Commanding.Groups.{CommandGroupEventRow, CommandGroupRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @group_kinds ~w(submitted approved approved_with_exclusions sent_back rejected aborted
                  released_on_contact hold_acknowledged member_canceled)
  @cap 200

  @type window :: %{optional(:from) => DateTime.t() | nil, optional(:to) => DateTime.t() | nil}

  @spec records(binary(), binary(), window()) :: map()
  def records(org, mission, window) do
    %{
      group_events: group_events(org, mission, window),
      group_cancels: group_cancels(org, mission, window),
      requests: requests(org, mission, window),
      approvals: approvals(org, mission, window),
      cancels: cancels(org, mission, window)
    }
  end

  @doc "A group's summary: id, title, command names in order, target count, own_values, sent_back_from."
  @spec groups(binary(), binary(), [binary()]) :: %{binary() => map()}
  def groups(_org, _mission, []), do: %{}

  def groups(org, mission, ids) do
    CommandGroupRow
    |> where(
      [g],
      g.organization_id == ^org and g.mission_id == ^mission and g.command_group_id in ^ids
    )
    |> select([g], %{
      id: g.command_group_id,
      title: g.title,
      commands: g.commands_document,
      targets: g.targets_document,
      sent_back_from: g.sent_back_from
    })
    |> Repo.all()
    |> Map.new(&{&1.id, summary(&1)})
  end

  @doc "When each group was sent back (its latest `sent_back` event), for the resent line."
  @spec sent_back_at(binary(), [binary()]) :: %{binary() => DateTime.t()}
  def sent_back_at(_mission, []), do: %{}

  def sent_back_at(mission, ids) do
    CommandGroupEventRow
    |> where(
      [e],
      e.mission_id == ^mission and e.command_group_id in ^ids and e.kind == "sent_back"
    )
    |> group_by([e], e.command_group_id)
    |> select([e], {e.command_group_id, max(e.at)})
    |> Repo.all()
    |> Map.new()
  end

  defp group_events(org, mission, window) do
    CommandGroupEventRow
    |> join(:inner, [e], g in CommandGroupRow, on: g.command_group_id == e.command_group_id)
    |> where(
      [e, g],
      e.mission_id == ^mission and g.organization_id == ^org and e.kind in ^@group_kinds
    )
    |> in_window(:at, window)
    |> order_by([e], desc: e.at, desc: e.event_id)
    |> limit(^@cap)
    |> select([e], {e.command_group_id, e})
    |> Repo.all()
    |> Enum.map(fn {id, row} ->
      row |> CommandGroupEventRow.to_domain() |> Map.put(:command_group_id, id)
    end)
    |> then(fn events ->
      groups = groups(org, mission, events |> Enum.map(& &1.command_group_id) |> Enum.uniq())
      Enum.map(events, &Map.put(&1, :group, Map.get(groups, &1.command_group_id)))
    end)
  end

  defp group_cancels(org, mission, window) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and
        not is_nil(r.command_group_id) and r.lifecycle_state == "canceled" and
        fragment(
          "?->'value'->'cancellation'->'actor'->>'actor_kind' = 'system'",
          r.metadata_document
        )
    )
    |> canceled_in_window(window)
    |> group_by([r], [
      r.command_group_id,
      fragment("?->'value'->'cancellation'->>'reason'", r.metadata_document)
    ])
    |> select([r], %{
      command_group_id: r.command_group_id,
      reason: fragment("?->'value'->'cancellation'->>'reason'", r.metadata_document),
      actor_id: min(fragment("?->'value'->'cancellation'->'actor'->>'id'", r.metadata_document)),
      count: count(r.command_request_id),
      at: max(fragment("(?->'value'->'cancellation'->>'at')::timestamptz", r.metadata_document)),
      endpoints: fragment("array_agg(DISTINCT ?)", r.source_endpoint_ref)
    })
    |> limit(^@cap)
    |> Repo.all()
    |> then(fn rows ->
      groups = groups(org, mission, rows |> Enum.map(& &1.command_group_id) |> Enum.uniq())
      Enum.map(rows, &Map.put(&1, :group, Map.get(groups, &1.command_group_id)))
    end)
  end

  defp requests(org, mission, window) do
    standalone(org, mission)
    |> where([r], not is_nil(r.requested_at))
    |> in_window(:requested_at, window)
    |> order_by([r], desc: r.requested_at)
    |> limit(^@cap)
    |> Repo.all()
    |> Enum.map(&CommandRequestRow.to_domain/1)
  end

  defp approvals(org, mission, window) do
    CommandApprovalRow
    |> join(:inner, [a], r in CommandRequestRow,
      on: r.command_request_id == a.command_request_id and r.mission_id == a.mission_id
    )
    |> where(
      [a, r],
      a.organization_id == ^org and a.mission_id == ^mission and not is_nil(a.decided_at) and
        is_nil(r.command_group_id) and a.decision != "not_required"
    )
    |> in_window(:decided_at, window)
    |> order_by([a], desc: a.decided_at)
    |> limit(^@cap)
    |> select([a, r], {a, r})
    |> Repo.all()
    |> Enum.map(fn {approval, request} ->
      %{
        approval: CommandApprovalRow.to_domain(approval),
        request: CommandRequestRow.to_domain(request)
      }
    end)
  end

  defp cancels(org, mission, window) do
    standalone(org, mission)
    |> where([r], r.lifecycle_state == "canceled")
    |> canceled_in_window(window)
    |> limit(^@cap)
    |> Repo.all()
    |> Enum.map(&CommandRequestRow.to_domain/1)
  end

  defp standalone(org, mission) do
    where(
      CommandRequestRow,
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and is_nil(r.command_group_id)
    )
  end

  defp in_window(query, field, window) do
    query
    |> then(fn q ->
      case window[:from] do
        %DateTime{} = from -> where(q, [r], field(r, ^field) >= ^from)
        _none -> q
      end
    end)
    |> then(fn q ->
      case window[:to] do
        %DateTime{} = to -> where(q, [r], field(r, ^field) < ^to)
        _none -> q
      end
    end)
  end

  defp canceled_in_window(query, window) do
    query
    |> where([r], not is_nil(fragment("?->'value'->'cancellation'->>'at'", r.metadata_document)))
    |> then(fn q ->
      case window[:from] do
        %DateTime{} = from ->
          where(
            q,
            [r],
            fragment("(?->'value'->'cancellation'->>'at')::timestamptz", r.metadata_document) >=
              ^from
          )

        _none ->
          q
      end
    end)
    |> then(fn q ->
      case window[:to] do
        %DateTime{} = to ->
          where(
            q,
            [r],
            fragment("(?->'value'->'cancellation'->>'at')::timestamptz", r.metadata_document) <
              ^to
          )

        _none ->
          q
      end
    end)
  end

  defp summary(row) do
    commands =
      row.commands
      |> JsonDocument.unwrap_value()
      |> List.wrap()
      |> Enum.sort_by(&(&1["position"] || 0))

    %{
      id: row.id,
      title: row.title,
      commands: Enum.map(commands, &(&1["name"] || &1["command_id"])),
      target_count: row.targets |> JsonDocument.unwrap_value() |> List.wrap() |> length(),
      # Targets with values of their own on any command (Compose "Per target").
      own_values:
        commands |> Enum.flat_map(&Map.keys(&1["per_target"] || %{})) |> Enum.uniq() |> length(),
      sent_back_from: row.sent_back_from
    }
  end
end
