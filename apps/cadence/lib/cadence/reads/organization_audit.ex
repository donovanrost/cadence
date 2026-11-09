defmodule Cadence.Reads.OrganizationAudit do
  @moduledoc """
  AU1, the organization audit log: who did what, merged from each domain's
  own records (there is no single audit store yet), newest first, with
  server-made action sentences.

  Sources: `config` (applied configuration revisions and settings changes),
  `commanding` (command requests and approval decisions), `access` (members
  joining, invitations sent), `alarms` (people acknowledging, assigning,
  handing off and annotating episodes), `contacts` (contact plan approval
  decisions) and `data` (data source definition changes). `sources.missing`
  is empty; it stays so the console can say when a source is absent.
  """

  alias Cadence.{Accounts, Missions}
  alias Cadence.Alarms.Queries, as: Alarms
  alias Cadence.Configuration.Status
  alias Cadence.Management.{Commanding, Contacts, DataSources}
  alias Cadence.Platform.ScopedSettings

  @included ~w(config commanding access alarms contacts data)
  @missing []
  @plan_cap 100
  @settings [
    {"cadence.governance", "Governance"},
    {"commanding.defaults", "Commanding"},
    {"cadence.configuration", "Configuration"},
    {"cadence.pass_review", "Pass review"}
  ]

  @doc """
  Options: `from`, `to` (DateTimes), `actor_id`, `mission_id`, `kinds` (list), `limit`,
  `offset`.
  """
  @spec list(binary(), map()) :: map()
  def list(organization_id, opts) do
    missions =
      organization_id
      |> Missions.list_missions()
      |> Enum.filter(&(is_nil(opts[:mission_id]) or &1.mission_id == opts[:mission_id]))

    events =
      (Enum.flat_map(missions, &mission_events(organization_id, &1, opts)) ++
         settings_events(organization_id, nil, nil) ++ access_events(organization_id))
      |> Enum.filter(&keep?(&1, opts))
      |> Enum.sort_by(& &1.at, {:desc, DateTime})

    page = events |> Enum.drop(opts.offset) |> Enum.take(opts.limit) |> with_actor_names()
    next = opts.offset + length(page)

    %{
      events: page,
      sources: %{included: @included, missing: @missing},
      next_offset: if(next < length(events), do: next)
    }
  end

  defp mission_events(organization_id, mission, opts) do
    ref = %{id: mission.mission_id, name: mission.display_name}
    id = mission.mission_id

    (revision_events(organization_id, id) ++
       settings_events(organization_id, id, ref) ++
       command_events(organization_id, id) ++
       alarm_events(id, opts) ++
       plan_events(organization_id, id) ++
       data_events(organization_id, id))
    |> Enum.map(fn event -> %{event | mission: event.mission || ref} end)
  end

  defp revision_events(organization_id, mission_id) do
    organization_id
    |> Status.list_revisions(mission_id, limit: 200)
    |> Enum.filter(& &1.applied_at)
    |> Enum.map(fn revision ->
      action =
        if revision.rolls_back_to,
          do: "Rolled back to r#{revision.rolls_back_to}",
          else: "Applied r#{revision.revision} · #{changes(revision.entry_count)}"

      event("config", revision.applied_at, revision.applied_by, action,
        target: %{
          kind: "revision",
          id: Integer.to_string(revision.revision),
          label: "r#{revision.revision}"
        },
        reason: revision.reason
      )
    end)
  end

  defp settings_events(organization_id, mission_id, mission) do
    for {section, title} <- @settings,
        entry <- ScopedSettings.history(organization_id, mission_id, section) do
      {:ok, at, _offset} = DateTime.from_iso8601(entry.saved_at)
      where = if mission_id, do: "", else: " (organization default)"

      event(
        "config",
        at,
        %{kind: "user", id: nil, name: entry.actor},
        "Changed #{title} settings#{where}",
        target: %{kind: "settings", id: section, label: title},
        mission: mission
      )
    end
  end

  defp command_events(organization_id, mission_id) do
    requests = Commanding.list_command_requests(organization_id, mission_id, [])
    names = Map.new(requests, &{&1.command_request_id, command_name(&1)})

    requested =
      requests
      |> Enum.filter(& &1.requested_at)
      |> Enum.map(fn request ->
        event(
          "commanding",
          request.requested_at,
          actor(request.requested_by),
          "Requested #{command_name(request)}",
          target: %{
            kind: "command_request",
            id: request.command_request_id,
            label: command_name(request)
          }
        )
      end)

    decided =
      organization_id
      |> Commanding.list_command_approvals(mission_id, [])
      |> Enum.filter(& &1.decided_at)
      |> Enum.map(fn approval ->
        name = Map.get(names, approval.command_request_id, "a command")

        event(
          "commanding",
          approval.decided_at,
          actor(approval.decided_by),
          "#{verb(approval.decision)} #{name}",
          target: %{kind: "command_request", id: approval.command_request_id, label: name},
          reason: approval.reason
        )
      end)

    requested ++ decided
  end

  defp alarm_events(mission_id, opts) do
    from = opts[:from] || ~U[2000-01-01 00:00:00Z]
    to = opts[:to] || DateTime.utc_now()

    mission_id
    |> Alarms.list_actions(from, to)
    |> Enum.map(fn action ->
      point = action.point_name || "an alarm"

      sentence = "#{alarm_verb(action.kind)} #{point}"

      event("alarms", action.at, actor(action.actor), sentence,
        target: %{kind: "alarm", id: action.episode_id, label: point},
        reason: (action.payload || %{})["note"]
      )
    end)
  end

  defp plan_events(organization_id, mission_id) do
    organization_id
    |> Contacts.list_plans(mission_id)
    |> Enum.take(@plan_cap)
    |> Enum.flat_map(fn {plan, _version} ->
      organization_id
      |> Contacts.list_approvals(mission_id, plan.contact_plan_id)
      |> Enum.map(fn approval ->
        event(
          "contacts",
          approval.decided_at,
          actor(approval.actor_document) ||
            %{kind: to_string(approval.actor_kind), id: approval.actor_id, name: nil},
          "#{verb(approval.decision)} contact plan v#{approval.contact_plan_version}",
          target: %{kind: "contact_plan", id: plan.contact_plan_id, label: "Contact plan"},
          reason: approval.reason
        )
      end)
    end)
  end

  defp data_events(organization_id, mission_id) do
    organization_id
    |> DataSources.source_event_page(mission_id, 1, nil)
    |> Map.get(:entries, [])
    |> Enum.filter(&(&1.mission_id == mission_id and is_binary(&1.actor_id)))
    |> Enum.map(fn source_event ->
      event(
        "data",
        source_event.occurred_at,
        %{kind: "user", id: source_event.actor_id, name: nil},
        "#{humanize(source_event.event_type)} data source #{source_event.data_source_id}",
        target: %{
          kind: "data_source",
          id: source_event.data_source_id,
          label: source_event.data_source_id
        }
      )
    end)
  end

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp access_events(organization_id) do
    joined =
      organization_id
      |> Accounts.list_member_directory()
      |> Enum.map(fn member ->
        event(
          "access",
          member.joined_at,
          %{kind: "user", id: member.user_id, name: member.display_name || member.email},
          "Joined as #{role(member.role)}",
          target: %{
            kind: "member",
            id: member.user_id,
            label: member.display_name || member.email
          }
        )
      end)

    invited =
      organization_id
      |> Accounts.list_invitation_directory()
      |> Enum.map(fn invitation ->
        event(
          "access",
          invitation.sent_at,
          %{kind: "user", id: nil, name: invitation.invited_by_name},
          "Invited #{invitation.email} as #{role(invitation.role)}",
          target: %{kind: "invitation", id: invitation.id, label: invitation.email}
        )
      end)

    joined ++ invited
  end

  defp event(kind, at, actor, action, opts) do
    %{
      id:
        "#{kind}:#{Keyword.get(opts, :target, %{})[:kind]}:#{Keyword.get(opts, :target, %{})[:id]}:#{DateTime.to_unix(to_utc(at), :microsecond)}",
      at: to_utc(at),
      actor: actor,
      kind: kind,
      action: action,
      target: Keyword.get(opts, :target),
      mission: Keyword.get(opts, :mission),
      reason: Keyword.get(opts, :reason)
    }
  end

  defp keep?(event, opts) do
    in_window?(event.at, opts[:from], opts[:to]) and
      (is_nil(opts[:actor_id]) or (event.actor || %{})[:id] == opts[:actor_id]) and
      (opts[:kinds] in [nil, []] or event.kind in opts[:kinds])
  end

  defp in_window?(at, from, to),
    do:
      (is_nil(from) or not DateTime.before?(at, from)) and
        (is_nil(to) or DateTime.before?(at, to))

  defp actor(%{"actor_kind" => kind} = doc),
    do: %{kind: kind, id: doc["user_id"] || doc["id"], name: doc["name"]}

  defp actor(%{"kind" => kind} = doc),
    do: %{kind: kind, id: doc["id"] || doc["user_id"], name: doc["name"] || doc["display_name"]}

  defp actor(%{kind: _} = actor), do: actor
  defp actor(_none), do: nil

  # Actor documents often carry only an id: name the people once per page.
  defp with_actor_names(events) do
    names =
      events
      |> Enum.flat_map(fn
        %{actor: %{id: id, name: nil}} when is_binary(id) -> [id]
        _named -> []
      end)
      |> Enum.uniq()
      |> Map.new(fn id ->
        case Accounts.fetch_user(id) do
          {:ok, user} -> {id, user.display_name || user.email}
          _system -> {id, nil}
        end
      end)

    Enum.map(events, fn
      %{actor: %{id: id, name: nil} = actor} = event when is_binary(id) ->
        %{event | actor: %{actor | name: Map.get(names, id)}}

      event ->
        event
    end)
  end

  defp command_name(request),
    do: request.command_display_name || request.command_name || request.command_id

  defp verb(:approved), do: "Approved"
  defp verb(:rejected), do: "Rejected"
  defp verb(decision), do: decision |> to_string() |> String.capitalize()

  defp changes(1), do: "1 change"
  defp changes(n), do: "#{n || 0} changes"

  defp role("organization_admin"), do: "organization admin"
  defp role(:organization_admin), do: "organization admin"
  defp role(other), do: to_string(other)

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
