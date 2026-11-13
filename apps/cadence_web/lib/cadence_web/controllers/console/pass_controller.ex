defmodule CadenceWeb.Console.PassController do
  @moduledoc """
  `GET /api/console/v1/missions/:mission_id/passes` (ops M7 = scheduling S1) and one pass,
  `GET …/passes/:id` (U32). Contract: docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.RepairChain
  alias Cadence.Contacts.{ProviderChangeAttention, ScheduleCommands}
  alias Cadence.Control.{Contacts, UplinkReadiness}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias Cadence.Reads.{Attention, Passes, PassUplink}
  alias CadenceWeb.Console.{PassJSON, Problem, WindowParams}

  @max_span_s 7 * 86_400
  @default_span_s 86_400
  @states ~w(requesting pending confirmed active completed unknown rejected canceling canceled failed)

  def index(conn, params) do
    with {:ok, window} <- WindowParams.parse(with_defaults(params), max_span_s: @max_span_s),
         {:ok, states} <- states(params["states"]) do
      result =
        Passes.load(org_id(conn), mission_id(conn), window.from, window.to, %{
          spacecraft_id: window.spacecraft_id,
          station: blank_to_nil(params["station"]),
          states: states
        })

      json(conn, %{data: PassJSON.passes(decorate(conn, result))})
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  def show(conn, %{"id" => id}) do
    case Passes.fetch(org_id(conn), mission_id(conn), id) do
      {:ok, pass} ->
        %{passes: [pass]} = decorate(conn, %{passes: [pass]})

        # D2 Release sheet: the groups that would lose this pass, and where they'd go instead.
        queued = PassUplink.queued_for_pass(org_id(conn), mission_id(conn), pass)

        json(conn, %{
          data:
            pass
            |> Map.put(:queued_command_groups, queued)
            |> Map.put(:provider_changes, provider_changes(conn, pass.id))
        })

      {:error, :pass_not_found} ->
        Problem.respond(conn, :pass_not_found)
    end
  end

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

    # A pass row carries its booking's pass_resolution item, else a pass_release one (a Release the
    # provider didn't confirm); a blocked uplink shows through uplink_readiness instead.
    {resolutions, blocked} =
      items
      |> Enum.sort_by(&attention_rank/1)
      |> Enum.split_with(&(&1.source in ["pass_resolution", "pass_release", "provider_change"]))

    conn
    |> with_replacements(result)
    |> with_attention(conn, resolutions)
    |> with_readiness(conn, Map.new(blocked, &{&1.contact_id, &1}))
    |> with_releasable(conn)
    |> with_bookers()
  end

  # L15: an off-plan booking names its booker (one batch of names per page).
  defp with_bookers(%{passes: passes} = result) do
    names =
      for %{off_plan: %{booked_by: %{id: id}}} <- passes, is_binary(id), uniq: true, into: %{} do
        case Cadence.Accounts.fetch_user(id) do
          {:ok, user} -> {id, user.display_name || user.email}
          _missing -> {id, nil}
        end
      end

    %{
      result
      | passes:
          Enum.map(passes, fn
            %{off_plan: %{booked_by: %{id: id}}} = pass when is_binary(id) ->
              put_in(pass, [:off_plan, :booked_by, :name], Map.get(names, id))

            pass ->
              pass
          end)
    }
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

            %{pass | releasable: (admin? or booker?) and pass.state in @releasable_states}
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

  # One item per pass, the highest rank winning (the last one kept): a booking resolution, then a
  # provider change awaiting approval (L14, fe-ops), another provider change, then a failed release.
  defp attention_rank(%{source: "pass_resolution"}), do: 3
  defp attention_rank(%{source: "provider_change", conflict: "approval_required"}), do: 2
  defp attention_rank(%{source: "provider_change"}), do: 1
  defp attention_rank(_item), do: 0

  defp with_attention(result, _conn, []), do: result

  defp with_attention(%{passes: passes} = result, conn, items) do
    names = AttentionItems.lookups(org_id(conn), mission_id(conn))
    by_reservation = Map.new(items, &{&1.provider_reservation_id, &1})

    %{
      result
      | passes:
          Enum.map(passes, fn pass ->
            case Map.get(by_reservation, pass.id) do
              nil -> pass
              item -> %{pass | attention: AttentionItems.object(item, names)}
            end
          end)
    }
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

  # Passes look forward: by default `from` is now and `to` is a day later.
  defp with_defaults(params) do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    from =
      case DateTime.from_iso8601(params["from"] || "") do
        {:ok, from, _offset} -> from
        _missing -> now
      end

    params
    |> Map.put_new_lazy("from", fn -> DateTime.to_iso8601(now) end)
    |> Map.put_new_lazy("to", fn -> DateTime.to_iso8601(DateTime.add(from, @default_span_s)) end)
  end

  defp states(nil), do: {:ok, nil}
  defp states(""), do: {:ok, nil}

  defp states(value) when is_binary(value) do
    states = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if Enum.all?(states, &(&1 in @states)),
      do: {:ok, states},
      else:
        {:error,
         {:invalid_params, %{"states" => "must be a comma list of #{Enum.join(@states, ", ")}"}}}
  end

  defp states(_value), do: {:error, {:invalid_params, %{"states" => "must be a comma list"}}}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
