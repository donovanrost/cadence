defmodule CadenceWeb.Console.ContactPlanWrites do
  @moduledoc """
  The S5 contact-plan writes' shared request and answer handling: submit
  (`ContactPlanController`) and approve (`ContactPlanReviewController`; #257, director 11-19).
  Params, the operation's answer (the original status and body, with `replayed`), starting the
  approved plan's execution off the request, and the refusals in the Problem envelope.
  Contract: docs/apogee/api/scheduling.md.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias Cadence.Control.Scheduling
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.Console.{ConfigJSON, PlanDetail, Problem, SchedulingRunner}

  # U36 / U76: one cap for the submitter's note and the approver's decision note.
  @note_max 2_000

  @doc "Submit's body: expected_version, operation_id, note, acknowledgements; no decision_note."
  @spec submit_params(map()) :: {:ok, map()} | {:error, map()}
  def submit_params(params) do
    with :ok <- no_decision_note(params["decision_note"]),
         {:ok, common} <- common(params),
         {:ok, note} <- note(params["note"], :note) do
      {:ok, Map.put(common, :note, note)}
    end
  end

  @doc "Approve's body: expected_version, operation_id, decision_note (as `note`), acknowledgements."
  @spec approve_params(map()) :: {:ok, map()} | {:error, map()}
  def approve_params(params) do
    with {:ok, common} <- common(params),
         {:ok, note} <- note(params["decision_note"], :decision_note) do
      {:ok, Map.put(common, :note, note)}
    end
  end

  @doc "The operation's answer: its original status and body, with `replayed` (#257)."
  @spec answer(Plug.Conn.t(), :submitted | :approved | :replayed, {pos_integer(), map()}) ::
          Plug.Conn.t()
  def answer(conn, kind, {status, body}) do
    conn
    |> put_status(status)
    |> json(%{data: Map.put(body, "replayed", kind == :replayed)})
  end

  @doc "Starts the approved version's execution off the request (it books with providers)."
  @spec start_execution(Plug.Conn.t(), binary(), pos_integer(), binary()) :: term()
  def start_execution(conn, plan_id, version, sha) do
    scope = conn.assigns.current_scope
    mission_id = mission_id(conn)

    SchedulingRunner.start(mission_id, :execute, plan_id, fn ->
      Scheduling.execute_plan(scope, mission_id, plan_id, version, sha)
    end)
  end

  @doc "A refused submit or approve in the Problem envelope."
  @spec refuse(Plug.Conn.t(), binary(), term()) :: Plug.Conn.t()
  def refuse(conn, _plan_id, {:contact_plan_already_submitted, details}),
    do: Problem.respond(conn, :plan_already_submitted, ConfigJSON.encode(details))

  def refuse(conn, _plan_id, {:contact_plan_self_approval_forbidden, because}),
    do:
      Problem.respond(conn, :contact_plan_self_approval_forbidden, %{
        because: Atom.to_string(because),
        via_service: nil
      })

  # #280 (U100): a service identity the approver is accountable for submitted or wrote it.
  def refuse(conn, _plan_id, {:contact_plan_self_approval_forbidden, because, via}),
    do:
      Problem.respond(conn, :contact_plan_self_approval_forbidden, %{
        because: Atom.to_string(because),
        via_service: via
      })

  def refuse(conn, _plan_id, {:contact_plan_approver_authors_unknown, details}),
    do: Problem.respond(conn, :contact_plan_approver_authors_unknown, details)

  def refuse(conn, plan_id, :contact_plan_not_pending_approval),
    do: Problem.respond(conn, :plan_not_pending, not_pending(conn, plan_id))

  def refuse(conn, plan_id, :duplicate_operation),
    do: Problem.respond(conn, :duplicate_operation, %{plan_id: plan_id})

  def refuse(conn, _plan_id, {:contact_plan_superseded, superseded}),
    do: Problem.respond(conn, :plan_superseded, ConfigJSON.encode(%{superseded: superseded}))

  def refuse(conn, plan_id, :contact_plan_not_satisfied) do
    details =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, plan} -> %{unmet: plan.unmet, conflicts: plan.conflicts}
        _missing -> nil
      end

    Problem.respond(conn, :plan_not_ready, ConfigJSON.encode(details))
  end

  def refuse(conn, _plan_id, {:contact_plan_exceptions_required, ids}),
    do: Problem.respond(conn, :acknowledgements_required, %{missing: ids})

  def refuse(conn, _plan_id, {:contact_plan_exceptions_unknown, ids}),
    do:
      Problem.respond(conn, :invalid_params, %{
        acknowledgements: "not unmet in this plan: #{Enum.join(ids, ", ")}"
      })

  def refuse(conn, _plan_id, {:contact_plan_exception_invalid, id}),
    do:
      Problem.respond(conn, :invalid_params, %{
        acknowledgements: "reason for #{id} must be 10-2000 characters"
      })

  def refuse(conn, _plan_id, details) when is_map(details),
    do: Problem.respond(conn, :invalid_params, details)

  def refuse(conn, _plan_id, reason)
      when reason in [:contact_plan_not_found, :contact_plan_version_not_found],
      do: Problem.respond(conn, :plan_not_found)

  def refuse(conn, _plan_id, reason)
      when reason in [
             :contact_plan_version_changed,
             :stale_contact_plan_version,
             :stale_contact_plan_content
           ],
      do: Problem.respond(conn, :plan_changed)

  def refuse(conn, _plan_id, :contact_plan_not_submittable),
    do: Problem.respond(conn, :plan_not_submittable)

  def refuse(conn, _plan_id, :operation_already_claimed),
    do: Problem.respond(conn, :operation_conflict)

  def refuse(conn, _plan_id, :forbidden), do: Problem.respond(conn, :forbidden)

  # U36: after a send back resubmits as a new version, this only means someone decided the
  # version concurrently; say who (lead's K1 reader: details.decided_by.name).
  def refuse(conn, plan_id, :contact_plan_version_already_decided) do
    decided_by =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, %{approval: %{actor: actor}}} -> actor
        _unknown -> nil
      end

    Problem.respond(conn, :contact_plan_version_already_decided, %{decided_by: decided_by})
  end

  def refuse(conn, _plan_id, reason) when is_atom(reason), do: Problem.respond(conn, reason)
  def refuse(conn, _plan_id, _reason), do: Problem.respond(conn, :plan_not_submittable)

  # #257: who decided last and when (both or neither, U29), and the plan's state now.
  defp not_pending(conn, plan_id) do
    state =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, plan} -> plan |> then(&PlanDetail.effective_state(conn, &1)) |> Map.get(:state)
        _missing -> nil
      end

    decision =
      case Scheduling.latest_decision(org_id(conn), mission_id(conn), plan_id) do
        %{actor_document: %{"id" => id} = actor, decided_at: at} ->
          # The plan read's own rule for a decider's name (ContactPlanOverview). Never the
          # email a row written before #466 may hold.
          name = actor["display_name"] || actor["name"]
          %{decided_by: %{id: id, name: name}, decided_at: at}

        _none ->
          %{decided_by: nil, decided_at: nil}
      end

    ConfigJSON.encode(Map.put(decision, :state, state))
  end

  defp common(params) do
    with {:ok, version} <- positive(params["expected_version"], :expected_version),
         {:ok, operation_id} <- operation_id(params["operation_id"]),
         {:ok, acknowledgements} <- acknowledgements(params["acknowledgements"]) do
      {:ok,
       %{
         expected_version: version,
         operation_id: operation_id,
         acknowledgements: acknowledgements
       }}
    end
  end

  # #257: submitting never approves, so it takes no decision note (approve does).
  defp no_decision_note(nil), do: :ok

  defp no_decision_note(_note),
    do:
      {:error,
       %{decision_note: "isn't taken on submit: approve with POST .../approve to record it"}}

  defp note(nil, _key), do: {:ok, nil}

  defp note(note, key) when is_binary(note) do
    case String.trim(note) do
      "" -> {:ok, nil}
      trimmed -> if String.length(trimmed) <= @note_max, do: {:ok, trimmed}, else: too_long(key)
    end
  end

  defp note(_note, key), do: {:error, %{key => "must be text"}}

  defp too_long(key), do: {:error, %{key => "Keep the note under 2,000 characters."}}

  defp acknowledgements(nil), do: {:ok, []}

  defp acknowledgements(items) when is_list(items) do
    if Enum.all?(
         items,
         &(is_map(&1) and is_binary(&1["requirement_id"]) and is_binary(&1["reason"]))
       ),
       do: {:ok, Enum.map(items, &%{requirement_id: &1["requirement_id"], reason: &1["reason"]})},
       else: {:error, %{acknowledgements: "must be [{requirement_id, reason}]"}}
  end

  defp acknowledgements(_items), do: {:error, %{acknowledgements: "must be a list"}}

  defp positive(value, _key) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(_value, key), do: {:error, %{key => "is required (positive integer)"}}

  defp operation_id(value) when is_binary(value) and byte_size(value) in 1..120, do: {:ok, value}
  defp operation_id(_value), do: {:error, %{operation_id: "is required (1-120 chars)"}}

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
