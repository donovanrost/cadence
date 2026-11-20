defmodule Cadence.Reads.OrganizationAudit do
  @moduledoc """
  AU1, the organization audit log: who did what, merged from each domain's
  own records (there is no single audit store yet), newest first, with
  server-made action sentences.

  Sources: `config` (applied configuration revisions and settings changes),
  `commanding` (command groups' decisions, Cadence's cancels folded per group, standalone
  requests' requests, decisions and cancels; `CommandEvents`), `access` (members
  joining, invitations sent), `alarms` (people acknowledging, assigning,
  handing off and annotating episodes), `contacts` (contact plan approval
  decisions), `data` (data source definition changes), `provider_accounts` and `account`
  (members' own password and session changes). `sources.missing`
  is empty; it stays so the console can say when a source is absent.
  """

  alias Cadence.Accounts.{MemberNames, MembershipAdministration}
  alias Cadence.Administration.PlatformAudit
  alias Cadence.Alarms.Queries, as: Alarms
  alias Cadence.Auth
  alias Cadence.Configuration.Status
  alias Cadence.Dashboards.ConfigAudit
  alias Cadence.Management.{Contacts, DataSources}
  alias Cadence.Missions

  alias Cadence.Reads.OrganizationAudit.{
    AccountEvents,
    CommandEvents,
    ContactEvents,
    DashboardEvents,
    ModelEvents,
    PolicyEvents,
    ProviderAccountEvents,
    SettingsEvents
  }

  @included ~w(config commanding access alarms contacts data provider_accounts account platform)
  @missing []
  @plan_cap 100

  @doc "The event kinds the log can contain (the `kinds` filter's values)."
  @spec kinds() :: [String.t()]
  def kinds, do: @included

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
         SettingsEvents.list(organization_id, nil, nil) ++
         access_events(organization_id) ++
         ProviderAccountEvents.list(organization_id) ++
         AccountEvents.list(organization_id) ++
         PlatformAudit.for_organization(organization_id))
      |> Enum.filter(&keep?(&1, opts))
      |> Enum.sort_by(& &1.at, {:desc, DateTime})

    page =
      events
      |> Enum.drop(opts.offset)
      |> Enum.take(opts.limit)
      |> named(organization_id)

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
       SettingsEvents.list(organization_id, id, ref) ++
       CommandEvents.list(organization_id, id, opts) ++
       alarm_events(id, opts) ++
       plan_events(organization_id, id) ++
       PolicyEvents.list(organization_id, id) ++
       ContactEvents.list(organization_id, id) ++
       ModelEvents.list(organization_id, id) ++
       data_events(organization_id, id) ++
       DashboardEvents.list(organization_id, id) ++
       ConfigAudit.list(organization_id, id))
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

  defp alarm_verb("acknowledged"), do: "Acknowledged"
  defp alarm_verb("assigned"), do: "Assigned"
  defp alarm_verb("unassigned"), do: "Unassigned"
  defp alarm_verb("handed_off"), do: "Handed off"
  defp alarm_verb("note"), do: "Added a note to"

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  # Who joined, was invited, accepted, had their role changed or was removed, and by whom
  # (MembershipAdministration.access_history/1).
  defp access_events(organization_id) do
    %{invitations: invitations, memberships: memberships} =
      MembershipAdministration.access_history(organization_id)

    people =
      organization_id
      |> MemberNames.ever_members(Enum.map(memberships, & &1.user_id))
      |> Map.new(fn {id, {name, _state}} -> {id, name} end)

    accepted = for i <- invitations, i.accepted_by, into: MapSet.new(), do: i.accepted_by

    Enum.flat_map(invitations, &invitation_events/1) ++
      Enum.flat_map(memberships, &membership_events(&1, people, accepted))
  end

  defp invitation_events(invitation) do
    target = %{kind: "invitation", id: invitation.id, label: invitation.email}

    [
      event(
        "access",
        invitation.sent_at,
        user(invitation.invited_by),
        "Invited #{invitation.email} as #{role(invitation.role)}",
        target: target
      ),
      invitation.accepted_at &&
        event(
          "access",
          invitation.accepted_at,
          user(invitation.accepted_by),
          "Accepted the invitation and joined as #{role(invitation.role)}",
          target: %{kind: "member", id: invitation.accepted_by, label: invitation.email}
        ),
      invitation.revoked_at &&
        event(
          "access",
          invitation.revoked_at,
          user(invitation.revoked_by),
          "Revoked the invitation for #{invitation.email}",
          target: target
        )
    ]
    |> Enum.reject(&(&1 in [nil, false]))
  end

  defp membership_events(membership, people, accepted) do
    label = Map.get(people, membership.user_id)
    target = %{kind: "member", id: membership.user_id, label: label}

    joined =
      if MapSet.member?(accepted, membership.user_id),
        do: [],
        else: [
          event(
            "access",
            membership.began_at,
            %{kind: "user", id: membership.user_id, name: label},
            "Joined as #{role(membership.role)}",
            target: target
          )
        ]

    joined ++
      for %{"at" => %DateTime{} = at} = recorded <- membership.events,
          do:
            event("access", at, user(recorded["by"]), administration(recorded, label),
              target: target
            )
  end

  defp administration(%{"action" => "role_changed", "from" => from, "to" => to}, label),
    do: "Changed #{label || "a member"}'s role from #{role(from)} to #{role(to)}"

  defp administration(%{"action" => "removed"}, label),
    do: "Removed #{label || "a member"} from the organization"

  defp administration(%{"action" => action}, _label), do: to_string(action)

  defp user(id) when is_binary(id), do: %{kind: "user", id: id, name: nil}
  defp user(_none), do: nil

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

  # #470: every actor on the page is named here, once, by the organization's own Audit rule
  # (setup.md C1 and its exception, OK'd by ca-security, ux and lead): a current member by their
  # display name (nil without one) with their id; a former member by their display name, with
  # no id; anyone else, a platform admin included, as {user, nil, nil}. A service by its live row in this
  # organization; another's as {service, nil, nil}. A name stored in an actor document is never
  # used for a person or a service (it can be an email from before #466/#471). Other kinds
  # (Cadence's own) keep theirs.
  @doc false
  def named(events, organization_id) do
    actors = Enum.map(events, & &1.actor)
    members = for %{target: %{kind: "member", id: id}} when is_binary(id) <- events, do: id
    users = MemberNames.ever_members(organization_id, actor_ids(actors, "user") ++ members)
    services = Auth.organization_service_identities(organization_id, actor_ids(actors, "service"))

    Enum.map(events, fn event ->
      %{event | actor: name(event.actor, users, services)} |> without_former_id(users)
    end)
  end

  # A former member's id isn't sent anywhere in the Audit (ca-security, #523): not as an actor,
  # not as a membership row's target, and not inside the event's id, which gets an opaque key.
  defp without_former_id(%{target: %{kind: "member", id: id} = target} = event, users)
       when is_binary(id) do
    case Map.get(users, id) do
      {_name, :active} ->
        event

      _former_or_unknown ->
        %{
          event
          | target: %{target | id: nil},
            id: String.replace(event.id, ":member:#{id}:", ":member:#{opaque(id)}:")
        }
    end
  end

  defp without_former_id(event, _users), do: event

  defp opaque(id),
    do:
      :crypto.hash(:sha256, "audit-member:" <> id)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 16)

  defp actor_ids(actors, kind),
    do: for(%{kind: ^kind, id: id} when is_binary(id) <- actors, uniq: true, do: id)

  defp name(%{kind: "user", id: id} = actor, users, _services) when is_binary(id) do
    case Map.fetch(users, id) do
      {:ok, {name, :active}} -> %{actor | name: name}
      # A former member is named, without their id (ca-security, #523).
      {:ok, {name, :former}} -> %{actor | id: nil, name: name}
      :error -> %{actor | id: nil, name: nil}
    end
  end

  defp name(%{kind: "service", id: id} = actor, _users, services) when is_binary(id) do
    case Map.fetch(services, id) do
      {:ok, name} -> %{actor | name: name}
      :error -> %{actor | id: nil, name: nil}
    end
  end

  defp name(%{kind: kind} = actor, _users, _services) when kind in ["user", "service"],
    do: %{actor | id: nil, name: nil}

  defp name(actor, _users, _services), do: actor

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
