defmodule CadenceWeb.Console.PassController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/passes` (ops M7 = scheduling S1) and one pass,
  `GET …/passes/:id` (U32). Contract: docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.RepairChain
  alias Cadence.Contacts.{ProviderChangeAttention, ScheduleCommands}
  alias Cadence.Control.{Contacts, UplinkReadiness}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias Cadence.Reads.{Attention, PassContactFields, Passes, PassUplink}
  alias CadenceWeb.Console.{PassJSON, PassListParams, Problem, WindowPageParams, WindowParams}

  @max_span_s 7 * 86_400

  def index(conn, params) do
    with {:ok, window} <-
           WindowParams.parse(PassListParams.with_defaults(params), max_span_s: @max_span_s),
         {:ok, filters} <- PassListParams.parse(params),
         {:ok, page} <- WindowPageParams.parse(params, 500),
         filters = filters |> Map.merge(page) |> Map.put(:spacecraft_id, window.spacecraft_id),
         {:ok, result} <-
           Passes.page(org_id(conn), mission_id(conn), window.from, window.to, filters) do
      json(conn, %{
        data: PassJSON.passes(decorate(conn, result)),
        meta: %{next_cursor: result.next_cursor}
      })
    else
      {:error, :invalid_cursor} -> WindowPageParams.cursor_error(conn)
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  def show(conn, %{"id" => id}) do
    # U78: a scheduled or realized contact id finds its pass too (writes take reservation ids).
    case Passes.resolve(org_id(conn), mission_id(conn), id) do
      {:ok, pass} ->
        %{passes: [pass]} = decorate(conn, %{passes: [pass]})

        # D2 Release sheet: the groups that would lose this pass, and where they'd go instead.
        queued = PassUplink.queued_for_pass(org_id(conn), mission_id(conn), pass)

        json(conn, %{
          data:
            pass
            |> Map.put(:queued_command_groups, queued)
            |> Map.put(:provider_changes, provider_changes(conn, pass.id))
            # U55/U56 queued requests and the provider's moves; U50 second connections refused.
            |> Map.merge(PassContactFields.detail(org_id(conn), mission_id(conn), pass, now()))
        })

      {:error, :pass_not_found} ->
        Problem.respond(conn, :pass_not_found)
    end
  end

  # U55: cancel or end the pass's contact, and how it ended.
  defp with_contact_fields(%{passes: passes} = result, conn),
    do: %{
      result
      | passes: PassContactFields.annotate(org_id(conn), mission_id(conn), passes, now())
    }

  defp now, do: DateTime.utc_now()

  defp decorate(conn, result) do
    items =
      case Attention.load(conn.assigns.current_scope, mission_id(conn)) do
        # A pass keeps its provider changes after it ends (Now drops them; domain fb09ac755).
        {:ok, %{items: items}} ->
          Enum.reject(items, &(&1.source == "provider_change")) ++
            ProviderChangeAttention.pass_items(org_id(conn), mission_id(conn))

        _forbidden ->
          []
      end

    # A pass row carries every open item of its booking (resolution, failed release, provider
    # change, a contact that didn't start, ingest pressure #83, archive quarantine #88, …): items
    # with no booking never match a row. A blocked uplink shows through uplink_readiness instead,
    # so only that source feeds the readiness map (any other could shadow command_groups_queued).
    {blocked, resolutions} = Enum.split_with(items, &(&1.source == "uplink_blocked"))

    conn
    |> with_replacements(result)
    |> with_attention(conn, resolutions)
    |> with_readiness(conn, Map.new(blocked, &{&1.contact_id, &1}))
    |> with_releasable(conn)
    |> with_bookers(org_id(conn))
    |> with_contact_fields(conn)
  end

  # L15: an off-plan booking names its booker (one batch of names per page). #146 (#468): only an
  # active member of the mission's organization is named and keeps their id; anyone else reads
  # id and name null, never an email. Runs after with_releasable, which compares the booker's id.
  defp with_bookers(%{passes: passes} = result, organization_id) do
    people =
      MemberNames.members(
        organization_id,
        for(%{off_plan: %{booked_by: %{id: id}}} <- passes, is_binary(id), do: id)
      )

    %{
      result
      | passes:
          Enum.map(passes, fn
            %{off_plan: %{booked_by: %{id: id}}} = pass when is_binary(id) ->
              update_in(pass, [:off_plan, :booked_by], &booker(&1, id, people))

            pass ->
              pass
          end)
    }
  end

  defp booker(booked_by, id, people) do
    case Map.fetch(people, id) do
      {:ok, name} -> %{booked_by | name: name}
      :error -> %{booked_by | id: nil, name: nil}
    end
  end

  @releasable_states ~w(pending confirmed active)

  # D2: org admins may release a live booking (the contact workspace's cancel rule); an off-plan
  # booking also by its booker (L15, DECISIONS #78).
  defp with_releasable(%{passes: passes} = result, conn) do
    admin? = may_release?(conn)
    viewer = conn.assigns.current_scope.user && conn.assigns.current_scope.user.user_id

    %{
      result
      | passes:
          Enum.map(passes, fn pass ->
            booker? =
              match?(%{off_plan: %{booked_by: %{id: ^viewer}}}, pass) and is_binary(viewer)

            # A hand-started contact (U78, booked: false) has no booking to release.
            %{
              pass
              | releasable:
                  Map.get(pass, :booked) == true and (admin? or booker?) and
                    pass.state in @releasable_states
            }
          end)
    }
  end

  # todo(authz): Cedar should decide who may release (cancel) a booking: today organization admins
  # (:manage_missions); perhaps per provider account or per spacecraft.
  defp may_release?(conn) do
    Policy.authorize(conn.assigns.current_scope, :manage_missions, %{
      organization_id: org_id(conn)
    }) == :ok
  end

  @doc "`POST …/passes/:id/release` (D2): cancels the booking at the provider."
  def release(conn, %{"id" => id} = params) do
    with :ok <- no_actor(params),
         {:ok, expected} <- expected_revision(params["expected_provider_revision"]),
         {:ok, reservation} <- reservation(conn, id),
         :ok <- releasable(reservation),
         :ok <- same_revision(reservation, expected),
         {:ok, _booking} <-
           ScheduleCommands.execute(conn.assigns.current_scope, mission_id(conn), "cancel", %{
             "reservation_evidence" => evidence(conn, reservation)
           }) do
      show(conn, %{"id" => id})
    else
      {:error, reason} -> release_problem(conn, reason)
    end
  end

  defp expected_revision(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp expected_revision(_value),
    do:
      {:error, {:invalid_params, %{"expected_provider_revision" => "must be a positive integer"}}}

  defp reservation(conn, id) do
    case Contacts.fetch_provider_reservation(org_id(conn), mission_id(conn), id) do
      {:ok, reservation} -> {:ok, reservation}
      _missing -> {:error, :pass_not_found}
    end
  end

  defp releasable(%{lifecycle_state: state, provider_contact_ref: ref}) when is_binary(ref) do
    if to_string(state) in @releasable_states, do: :ok, else: {:error, :pass_not_releasable}
  end

  defp releasable(_reservation), do: {:error, :pass_not_releasable}

  defp same_revision(%{provider_revision: revision}, revision), do: :ok
  defp same_revision(_reservation, _expected), do: {:error, :pass_changed}

  # The exact booking the viewer saw (ScheduleCancellations' reviewed evidence).
  defp evidence(conn, reservation),
    do: %{
      "contract_version" => 1,
      "organization_id" => org_id(conn),
      "mission_id" => mission_id(conn),
      "reservation_id" => reservation.provider_reservation_id,
      "provider_revision" => reservation.provider_revision,
      "lifecycle_state" => to_string(reservation.lifecycle_state),
      "provider_contact_ref" => reservation.provider_contact_ref
    }

  defp release_problem(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp release_problem(conn, {:actor_not_assignable, keys}),
    do: Problem.respond(conn, :actor_not_assignable, %{fields: keys})

  # The provider refused, or the outcome is unknown: the booking is as domain left it (4b18d046).
  defp release_problem(conn, {:provider_reservation_not_confirmed, reservation}) do
    error = JsonDocument.unwrap_value(reservation.last_error_document) || %{}

    Problem.respond(conn, :provider_cancel_failed, %{
      outcome: error["outcome"],
      reason: error["reason"],
      state: to_string(reservation.lifecycle_state)
    })
  end

  defp release_problem(conn, reason)
       when reason in [:pass_not_found, :pass_not_releasable],
       do: Problem.respond(conn, reason)

  # The booking changed since the viewer opened it: send its current row so D2 can reload.
  defp release_problem(conn, :pass_changed), do: pass_changed(conn)

  defp release_problem(conn, :invalid_reservation_cancellation_evidence), do: pass_changed(conn)

  defp release_problem(conn, reason) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp pass_changed(conn) do
    pass =
      case Passes.fetch(org_id(conn), mission_id(conn), conn.path_params["id"]) do
        {:ok, pass} -> hd(decorate(conn, %{passes: [pass]}).passes)
        _missing -> nil
      end

    Problem.respond(conn, :pass_changed, %{pass: pass})
  end

  # U32: each booking's open or acknowledged pass-resolution item (the drawer's attention block),
  # for viewers who operate the mission. A blocked uplink shows in `uplink_readiness` instead.
  # ux U44's pass history: every change of the pass, decided ones with their resolution.
  defp provider_changes(conn, reservation_id) do
    org_id(conn)
    |> ProviderChangeAttention.pass_history(mission_id(conn), reservation_id)
    |> Enum.map(fn change ->
      change
      |> AttentionItems.provider_change()
      |> Map.update(:resolution, nil, &resolution/1)
    end)
  end

  defp resolution(nil), do: nil

  defp resolution(%{by: by} = resolution),
    do: %{resolution | by: person(by)}

  defp person(%{"kind" => "user", "id" => id} = by), do: %{id: id, name: by["name"]}
  defp person(_system), do: nil

  # ux U45: every open item of the pass in Now's order (priority, the soonest due, then a
  # contact that didn't start), each with its priority and due_at; `attention` is the first.
  defp with_attention(%{passes: passes} = result, conn, items) do
    now = DateTime.utc_now()
    names = AttentionItems.lookups(org_id(conn), mission_id(conn), items)

    by_reservation =
      items
      |> Enum.map(fn item ->
        {priority, due_at} = AttentionItems.rank(item, now)

        {item,
         item |> AttentionItems.object(names) |> Map.merge(%{priority: priority, due_at: due_at})}
      end)
      |> Enum.sort_by(fn {item, object} -> order(item, object) end)
      |> Enum.group_by(
        fn {item, _object} -> Map.get(item, :provider_reservation_id) end,
        &elem(&1, 1)
      )

    %{
      result
      | passes:
          Enum.map(passes, fn pass ->
            attentions = Map.get(by_reservation, pass.id, [])
            Map.merge(pass, %{attention: List.first(attentions), attentions: attentions})
          end)
    }
  end

  # A null due_at sorts after any time; on a tie, a contact that didn't start comes first.
  defp order(item, %{priority: priority, due_at: due_at}) do
    due = if due_at, do: {0, DateTime.to_unix(due_at, :microsecond)}, else: {1, 0}
    {priority, due, if(item.source == "contact_start", do: 0, else: 1)}
  end

  # U33: live uplink readiness per pass.
  defp with_readiness(%{passes: passes} = result, conn, blocked),
    do: %{
      result
      | passes: PassUplink.put_readiness(org_id(conn), mission_id(conn), passes, blocked)
    }

  @doc "`POST …/passes/:id/recover-uplink` (U33): re-runs the pass's uplink qualification."
  # todo(authz): Cedar should decide who may recover an uplink (any mission operator today,
  # DECISIONS #58), e.g. only operators of that ground network or spacecraft.
  def recover_uplink(conn, %{"id" => id} = params) do
    with :ok <- no_actor(params),
         {:ok, %{scheduled_contact_id: contact_id}} when is_binary(contact_id) <-
           Contacts.fetch_provider_reservation(org_id(conn), mission_id(conn), id),
         {:ok, outcome} <-
           UplinkReadiness.recover(conn.assigns.current_scope, mission_id(conn), contact_id) do
      json(conn, %{
        data: %{state: to_string(outcome.state), ready_at: Map.get(outcome, :ready_at)}
      })
    else
      {:error, {:actor_not_assignable, keys}} ->
        Problem.respond(conn, :actor_not_assignable, %{fields: keys})

      {:error, {:refused, reason}} ->
        Problem.respond(conn, :uplink_recovery_refused, %{reason: to_string(reason)})

      {:error, :not_blocked} ->
        Problem.respond(conn, :uplink_not_blocked)

      {:error, :forbidden} ->
        Problem.respond(conn, :forbidden)

      _not_found ->
        Problem.respond(conn, :pass_not_found)
    end
  end

  defp no_actor(params) do
    case Enum.filter(
           ~w(actor actor_id actor_kind user_id recovered_by by),
           &Map.has_key?(params, &1)
         ) do
      [] -> :ok
      keys -> {:error, {:actor_not_assignable, keys}}
    end
  end

  # qa #30: a lost booking that an applied repair replaced says by which plan and booking.
  defp with_replacements(conn, %{passes: passes} = result) do
    replaced =
      RepairChain.replacements_for(
        org_id(conn),
        mission_id(conn),
        for(%{plan: %{id: plan_id}, ended_by: %{}} <- passes, do: plan_id)
      )

    %{result | passes: Enum.map(passes, &Map.put(&1, :replaced_by, Map.get(replaced, &1.id)))}
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
