defmodule Cadence.Reads.PassContactRecord do
  @moduledoc """
  L14 / parity A13 (fe-ops, ux U74): a pass's contact record for the drawer's Technical details,
  what the legacy contact record page showed. Give it a scheduled OR a realized contact id; it reads
  both sides of the pair.

    * `scheduled` / `realized`: their ids, states, window, clock mode;
    * `paths`: each side's paths with the bindings themselves (the legacy page only counted them);
    * `sources` and `intents`: the current schedule's and the realized contact's;
    * `revisions`: the schedule history, newest first, 25 per page (`revisions_cursor`), each with
      its window and state, so "Review current revision" is just picking one.

  Caps: 100 paths, 200 sources, 200 intents, then `truncated: true`.
  Contract: docs/apogee/api/contacts.md § Contact record.
  """

  alias Cadence.Accounts
  alias Cadence.Accounts.MemberNames
  alias Cadence.Control.Contacts

  @max_paths 100
  @max_listed 200

  @spec load(binary(), binary(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, :contact_not_found | :invalid_cursor}
  def load(org, mission, contact_id, revisions_cursor \\ nil) do
    with {:ok, cursor} <- cursor(revisions_cursor),
         {:ok, kind, scheduled, realized} <- subject(org, mission, contact_id),
         {:ok, revisions} <- revisions(org, mission, scheduled, cursor) do
      current = current_revision(org, mission, scheduled)
      paths = paths("scheduled", scheduled) ++ paths("realized", realized)
      sources = sources(current, realized)
      intents = intents(scheduled, realized)

      {:ok,
       %{
         subject: %{id: contact_id, kind: kind},
         scheduled: scheduled && scheduled_view(scheduled),
         realized: realized && realized_view(realized),
         paths: Enum.take(paths, @max_paths),
         sources: Enum.take(sources, @max_listed),
         intents: Enum.take(intents, @max_listed),
         revisions: revisions,
         truncated:
           length(paths) > @max_paths or length(sources) > @max_listed or
             length(intents) > @max_listed
       }}
    end
  end

  defp cursor(nil), do: {:ok, nil}

  defp cursor(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..2_147_483_647 -> {:ok, n}
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp subject(org, mission, id) do
    case {Contacts.fetch_scheduled_contact(org, mission, id),
          Contacts.fetch_realized_contact(org, mission, id)} do
      {{:ok, scheduled}, _} ->
        {:ok, "scheduled", scheduled,
         linked(org, mission, :realized, scheduled.realized_contact_id)}

      {_, {:ok, realized}} ->
        {:ok, "realized", linked(org, mission, :scheduled, realized.scheduled_contact_id),
         realized}

      _neither ->
        {:error, :contact_not_found}
    end
  end

  defp linked(_org, _mission, _side, nil), do: nil

  defp linked(org, mission, :realized, id) do
    case Contacts.fetch_realized_contact(org, mission, id) do
      {:ok, realized} -> realized
      _missing -> nil
    end
  end

  defp linked(org, mission, :scheduled, id) do
    case Contacts.fetch_scheduled_contact(org, mission, id) do
      {:ok, scheduled} -> scheduled
      _missing -> nil
    end
  end

  defp revisions(_org, _mission, nil, _cursor), do: {:ok, %{entries: [], next_cursor: nil}}

  defp revisions(org, mission, scheduled, cursor) do
    case Contacts.list_scheduled_contact_revisions_page(
           org,
           mission,
           scheduled.scheduled_contact_id,
           scheduled.current_revision,
           cursor
         ) do
      {:ok, page} ->
        people = MemberNames.members(org, Enum.map(page.entries, & &1.created_by))

        {:ok,
         %{
           entries: Enum.map(page.entries, &revision(&1, people)),
           next_cursor: page.next && Integer.to_string(page.next)
         }}

      {:error, _bad_cursor} ->
        {:error, :invalid_cursor}
    end
  end

  defp current_revision(_org, _mission, nil), do: nil

  defp current_revision(org, mission, scheduled) do
    case Contacts.fetch_scheduled_contact_revision(
           org,
           mission,
           scheduled.scheduled_contact_id,
           scheduled.current_revision
         ) do
      {:ok, revision} -> revision
      _missing -> nil
    end
  end

  defp scheduled_view(s),
    do: %{
      id: s.scheduled_contact_id,
      current_revision: s.current_revision,
      lifecycle_state: to_string(s.lifecycle_state),
      starts_at: s.starts_at,
      ends_at: s.ends_at,
      realized_id: s.realized_contact_id,
      provider_contact_ref: s.provider_contact_ref
    }

  defp realized_view(r),
    do: %{
      id: r.realized_contact_id,
      scheduled_id: r.scheduled_contact_id,
      lifecycle_state: to_string(r.lifecycle_state),
      clock_mode: r.clock_mode && to_string(r.clock_mode),
      realized_at: r.realized_at,
      initial_time: r.initial_time
    }

  defp revision(r, people) do
    snapshot = r.snapshot_document || %{}

    %{
      revision: r.revision,
      created_at: r.created_at,
      created_by: creator(r.created_by, people),
      provider_change_id: r.provider_reservation_change_id,
      starts_at: snapshot["starts_at"],
      ends_at: snapshot["ends_at"],
      lifecycle_state: snapshot["lifecycle_state"]
    }
  end

  defp paths(_side, nil), do: []

  defp paths(side, contact) do
    Enum.map(contact.paths || [], fn p ->
      %{
        side: side,
        id: p.path_id,
        direction: p.direction && to_string(p.direction),
        selection: p.selection_role && to_string(p.selection_role),
        source_endpoint_ref: p.source_endpoint_ref,
        provider_bindings:
          Enum.map(
            p.provider_bindings || [],
            &%{id: &1.provider_binding_id, adapter_key: text(&1.adapter_key)}
          ),
        transport_bindings:
          Enum.map(
            p.transport_bindings || [],
            &%{
              id: &1.transport_binding_id,
              family_key: text(&1.family_key),
              target_scope: text(&1.target_scope)
            }
          )
      }
    end)
  end

  defp sources(current, realized) do
    planned =
      if(current, do: (current.snapshot_document || %{})["source_endpoint_refs"] || [], else: [])

    actual = if(realized, do: realized.source_endpoint_refs || [], else: [])
    tagged(planned, "reviewed_schedule") ++ tagged(actual, "realized")
  end

  defp intents(scheduled, realized) do
    planned = if(scheduled, do: Enum.map(scheduled.contact_intents || [], &to_string/1), else: [])
    actual = if(realized, do: Enum.map(realized.contact_intents || [], &to_string/1), else: [])
    tagged(planned, "current_schedule") ++ tagged(actual, "realized")
  end

  defp tagged(values, side), do: values |> Enum.uniq() |> Enum.map(&%{id: &1, side: side})

  # As plan history's created_by: a person, Cadence itself, or an id we can't name. A person is
  # named, and keeps their id, only while an active member of the mission's organization
  # (`people`, one lookup per page; #146, #468); any other person reads id and name nil.
  defp creator(nil, _people), do: nil
  defp creator("cadence" <> _ = id, _people), do: %{kind: "system", id: id, name: "Cadence"}
  defp creator("system" <> _ = id, _people), do: %{kind: "system", id: id, name: "Cadence"}

  defp creator(id, people) when is_binary(id) do
    case Map.fetch(people, id) do
      {:ok, name} -> %{kind: "user", id: id, name: name}
      :error -> outsider(id)
    end
  end

  defp creator(_other, _people), do: nil

  # Only for ids that aren't members: whether the id is a person at all.
  defp outsider(id) do
    case Accounts.fetch_user(id) do
      {:ok, _person} -> %{kind: "user", id: nil, name: nil}
      _other -> %{kind: nil, id: id, name: nil}
    end
  end

  defp text(nil), do: nil
  defp text(value), do: to_string(value)
end
