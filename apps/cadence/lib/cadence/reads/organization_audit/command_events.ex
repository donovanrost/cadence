defmodule Cadence.Reads.OrganizationAudit.CommandEvents do
  @moduledoc """
  The audit's `commanding` entries (director 11-15, ux U59), from records commanding already
  keeps (`Commanding.Groups.AuditRecords`); nothing is written for the audit.

    * A command group is one entry per decision (submitted or resent, GO, GO excluding, NO-GO,
      sent back, aborted, released on a contact, HOLD acknowledged, a member canceled by an
      operator), targeted `{kind: "command_group", id, label}`, never one row per member.
    * Cadence's own cancels of a group's members fold to one entry per group and reason, by
      the actor Cadence (`kind: "service"`).
    * A standalone request keeps its own entries: requested, approved or rejected, canceled.

  Bounded by the page's `from`/`to` in SQL and capped (`Commanding.Groups.AuditRecords`).
  """

  alias Cadence.Commanding.Groups.AuditRecords
  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Management.Commanding
  alias Cadence.Reads.OrganizationAudit.CommandLines, as: Lines
  alias Cadence.SpacecraftStore

  @kind "commanding"

  @spec list(binary(), binary(), map()) :: [map()]
  def list(org, mission, opts) do
    records =
      AuditRecords.records(org, mission, %{from: opts[:from], to: opts[:to]})

    names = if names?(records), do: spacecraft_names(org, mission), else: %{}
    ctx = %{org: org, mission: mission, names: &Map.get(names, &1)}
    resent = resent(records, ctx)

    (Enum.map(records.group_events, &group_event(&1, ctx, resent)) ++
       Enum.map(records.group_cancels, &group_cancel(&1, ctx)) ++
       Enum.map(records.requests, &requested/1) ++
       Enum.map(records.approvals, &decided/1) ++
       Enum.map(records.cancels, &request_canceled(&1, ctx)))
    |> Enum.reject(&is_nil(&1.at))
  end

  # -- groups -------------------------------------------------------------------------------

  defp group_event(%{kind: kind} = event, ctx, resent) do
    group = event.group
    payload = event.payload || %{}

    {line, reason} =
      case to_string(kind) do
        "submitted" ->
          {Lines.submitted(event, group, Map.get(resent, event.command_group_id)), nil}

        decided when decided in ~w(approved approved_with_exclusions rejected sent_back) ->
          {Lines.decision(decided, payload, group), payload["note"]}

        "aborted" ->
          {Lines.aborted(payload, group), payload["reason"]}

        "released_on_contact" ->
          {Lines.released(payload, group, contact(ctx, payload["realized_contact_id"])), nil}

        "hold_acknowledged" ->
          {Lines.hold_acknowledged(payload, group), payload["note"]}

        "member_canceled" ->
          {member_canceled(ctx, payload, group), payload["reason"]}
      end

    entry(event.at, actor(event.actor), line, group_target(event.command_group_id, group),
      id: "command_group_event:" <> event.id,
      reason: reason
    )
  end

  defp member_canceled(ctx, payload, group) do
    case Commanding.fetch_command_request(ctx.org, ctx.mission, payload["command_request_id"]) do
      {:ok, request} ->
        Lines.member_canceled(
          command_name(request),
          ctx.names.(request.source_endpoint_ref),
          group
        )

      _gone ->
        Lines.member_canceled("a command", nil, group)
    end
  end

  defp group_cancel(row, ctx) do
    archived =
      row.endpoints
      |> List.wrap()
      |> Enum.map(ctx.names)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    line = Lines.group_canceled(row.count, row.reason, archived, row.group)

    entry(row.at, cadence(row.actor_id), line, group_target(row.command_group_id, row.group),
      id: "command_group_cancel:#{row.command_group_id}:#{row.reason}"
    )
  end

  # Resent groups: when the original was sent back, and its title.
  defp resent(%{group_events: events}, ctx) do
    originals =
      for %{kind: kind, group: %{sent_back_from: from}} <- events,
          to_string(kind) == "submitted" and is_binary(from),
          uniq: true,
          do: from

    summaries = AuditRecords.groups(ctx.org, ctx.mission, originals)
    times = AuditRecords.sent_back_at(ctx.mission, originals)

    for %{kind: kind, command_group_id: id, group: %{sent_back_from: from}} <- events,
        to_string(kind) == "submitted" and is_binary(from),
        into: %{} do
      {id, %{at: Map.get(times, from), title: get_in(summaries, [from, :title])}}
    end
    |> Map.reject(fn {_id, resent} -> is_nil(resent.at) end)
  end

  defp contact(_ctx, nil), do: nil

  defp contact(ctx, realized_contact_id) do
    case Contacts.fetch_realized_contact(ctx.org, ctx.mission, realized_contact_id) do
      {:ok, contact} ->
        stations = StationRefs.index(ctx.org, ctx.mission)
        station = StationRefs.resolve((contact.metadata || %{})["ground_station_ref"], stations)
        %{code: station.code, at: contact.realized_at}

      _gone ->
        nil
    end
  end

  defp group_target(id, group),
    do: %{kind: "command_group", id: id, label: Lines.label(group)}

  # -- standalone requests ----------------------------------------------------------------

  defp requested(request) do
    name = command_name(request)

    entry(
      request.requested_at,
      actor(request.requested_by),
      "Requested #{name}",
      request_target(request.command_request_id, name),
      id: "command_request:requested:" <> request.command_request_id
    )
  end

  defp decided(%{approval: approval, request: request}) do
    name = command_name(request)

    entry(
      approval.decided_at,
      actor(approval.decided_by),
      "#{verb(approval.decision)} #{name}",
      request_target(approval.command_request_id, name),
      id: "command_approval:" <> approval.command_approval_id,
      reason: approval.reason
    )
  end

  defp request_canceled(request, ctx) do
    cancellation = (request.metadata || %{})["cancellation"] || %{}
    by = cancellation["actor"] || %{}
    system? = (by["actor_kind"] || by["kind"]) == "system"
    name = command_name(request)
    spacecraft = if system?, do: ctx.names.(request.source_endpoint_ref)
    line = Lines.request_canceled(name, spacecraft, system?, cancellation["reason"])

    entry(
      parse(cancellation["at"]),
      if(system?, do: cadence(by["id"]), else: actor(by)),
      line,
      request_target(request.command_request_id, name),
      id: "command_request:canceled:" <> request.command_request_id,
      reason: if(system?, do: nil, else: cancellation["reason"])
    )
  end

  defp request_target(id, name), do: %{kind: "command_request", id: id, label: name}

  # -- shared -------------------------------------------------------------------------------

  defp entry(at, actor, action, target, opts) do
    %{
      id: "#{@kind}:" <> Keyword.fetch!(opts, :id),
      at: at,
      actor: actor,
      kind: @kind,
      action: action,
      target: target,
      mission: nil,
      reason: Keyword.get(opts, :reason)
    }
  end

  defp cadence(id), do: %{kind: "service", id: id, name: "Cadence"}

  defp actor(%{"actor_kind" => kind} = doc),
    do: %{kind: kind, id: doc["user_id"] || doc["id"], name: doc["name"]}

  defp actor(%{"kind" => kind} = doc),
    do: %{kind: kind, id: doc["id"] || doc["user_id"], name: doc["name"] || doc["display_name"]}

  defp actor(_none), do: nil

  # Spacecraft names by uplink endpoint, loaded only when a line names one.
  defp names?(records) do
    Enum.any?(records.group_events, &(to_string(&1.kind) == "member_canceled")) or
      Enum.any?(records.group_cancels, &names_spacecraft?(&1.reason)) or
      records.cancels != []
  end

  defp names_spacecraft?(reason),
    do: String.starts_with?(reason || "", ["spacecraft_archived", "commanding_disabled"])

  defp spacecraft_names(org, mission) do
    crafts =
      org
      |> SpacecraftStore.list_spacecraft(mission)
      |> Map.new(&{&1.spacecraft_id, &1.display_name})

    org
    |> Groups.spacecraft_by_endpoint(mission)
    |> Map.new(fn {ref, id} -> {ref, Map.get(crafts, id)} end)
  end

  defp parse(%DateTime{} = at), do: at

  defp parse(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, parsed, _offset} -> parsed
      _invalid -> nil
    end
  end

  defp parse(_none), do: nil

  defp command_name(request),
    do: request.command_display_name || request.command_name || request.command_id

  defp verb(:approved), do: "Approved"
  defp verb(:rejected), do: "Rejected"
  defp verb(decision), do: decision |> to_string() |> String.capitalize()
end
