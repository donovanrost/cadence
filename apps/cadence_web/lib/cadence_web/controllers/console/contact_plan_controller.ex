defmodule CadenceWeb.Console.ContactPlanController do
  @moduledoc """
  Contact plan reads for scheduling (S6 list, plan detail with demand).
  Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.ContactPlan
  alias Cadence.Control.{PlanningTemplates, Scheduling}
  alias Cadence.Reads.{ContactPlanOverview, PlanAlternatives, PlanningSetup}
  alias CadenceWeb.Console.{ConfigJSON, PlanDetail, Problem, SchedulingRunner}

  @states Map.new(ContactPlan.states(), &{Atom.to_string(&1), &1})
  # Derived states (§Plan states): the stored state doesn't say, so they filter after deriving.
  @derived %{"interrupted" => :interrupted, "unconfirmed" => :unconfirmed}

  def index(conn, params) do
    with {:ok, day} <- day(params["day"]),
         {:ok, state} <- state(params["state"]) do
      derived? = state in Map.values(@derived)
      stored = if derived?, do: nil, else: state

      plans =
        org_id(conn)
        |> ContactPlanOverview.list(mission_id(conn), %{day: day, state: stored})
        |> Enum.map(&PlanDetail.effective_state(conn, &1))
        |> Enum.filter(&(not derived? or &1.state == state))

      # U28: repair proposals come apart from the plans, so K1 picks the base plan and points to
      # its repair.
      {proposals, base} = Enum.split_with(plans, &(&1.repair_of != nil))
      json(conn, %{data: ConfigJSON.encode(%{plans: base, repair_proposals: proposals})})
    else
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  def show(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, version} <- version(params["version"]),
         {:ok, plan} <- ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id, version) do
      json(conn, %{data: ConfigJSON.encode(PlanDetail.build(conn, plan))})
    else
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  @doc """
  Whether drafting is possible (policy + requirements), before offering Draft, plus (U52) the template fan-out Start would count for `?day=` (UTC,
  default today) against the 50,000 limit, and the templates its per-run cap cuts short.
  """
  def setup(conn, params) do
    case day(params["day"]) do
      {:ok, day} ->
        setup =
          org_id(conn)
          |> PlanningSetup.setup(mission_id(conn))
          |> Map.put(:template_requirements_estimate, estimate(conn, day || Date.utc_today()))

        json(conn, %{data: ConfigJSON.encode(%{setup: setup})})

      {:error, details} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  # null when there's nothing to count (no active template) or no estimate.
  defp estimate(conn, day) do
    case Scheduling.draft_template_estimate(conn.assigns.current_scope, mission_id(conn), day) do
      {:ok, %{count: 0, capped: []}} ->
        nil

      {:ok, %{count: count, limit: limit, capped: capped}} ->
        names = template_names(conn, capped)

        %{
          count: count,
          limit: limit,
          capped:
            Enum.map(capped, fn cut ->
              %{
                template: %{id: cut.template_id, name: Map.get(names, cut.template_id)},
                limit: cut.limit,
                last_at: cut.last_at
              }
            end)
        }

      _unavailable ->
        nil
    end
  end

  defp template_names(_conn, []), do: %{}

  defp template_names(conn, _capped) do
    org_id(conn)
    |> PlanningTemplates.list(mission_id(conn))
    |> Map.new(&{&1.id, &1.name})
  end

  @doc "Contact demand for a UTC day without a plan (S2)."
  def demand(conn, params) do
    case day(params["day"]) do
      {:ok, %Date{} = day} ->
        json(conn, %{
          data: ConfigJSON.encode(PlanningSetup.demand(org_id(conn), mission_id(conn), day))
        })

      {:ok, nil} ->
        Problem.respond(conn, :invalid_params, %{day: "is required (YYYY-MM-DD)"})

      {:error, details} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  @doc "S4: add/remove passes as a new plan version; returns the new plan detail."
  def edit(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, version} <- positive(params["expected_version"], :expected_version),
         {:ok, add} <- ids(params["add"], :add),
         {:ok, remove} <- ids(params["remove"], :remove),
         {:ok, _plan, new_version} <-
           Scheduling.edit_plan(scope(conn), mission_id(conn), plan_id, version, add, remove),
         {:ok, plan} <-
           ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id, new_version.version) do
      json(conn, %{data: ConfigJSON.encode(PlanDetail.build(conn, plan))})
    else
      {:error, details} when is_map(details) ->
        Problem.respond(conn, :invalid_params, details)

      {:error, :contact_plan_version_changed} ->
        Problem.respond(conn, :plan_changed)

      {:error, reason} when reason in [:contact_plan_not_found, :plan_not_found] ->
        Problem.respond(conn, :plan_not_found)

      {:error, reason} when is_atom(reason) ->
        Problem.respond(conn, :plan_not_editable, %{reason: Atom.to_string(reason)})

      _other ->
        Problem.respond(conn, :plan_not_editable)
    end
  end

  @doc "S4: unselected opportunities for one spacecraft with their effect if added."
  def alternatives(conn, %{"plan_id" => plan_id} = params) do
    with spacecraft_id when is_binary(spacecraft_id) and spacecraft_id != "" <-
           params["spacecraft_id"],
         {:ok, result} <-
           PlanAlternatives.load(org_id(conn), mission_id(conn), plan_id, spacecraft_id) do
      json(conn, %{data: ConfigJSON.encode(result)})
    else
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
      _missing -> Problem.respond(conn, :invalid_params, %{spacecraft_id: "is required"})
    end
  end

  defp ids(nil, _key), do: {:ok, []}

  defp ids(list, key) when is_list(list) do
    if Enum.all?(list, &is_binary/1),
      do: {:ok, list},
      else: {:error, %{key => "must be a list of snapshot ids"}}
  end

  defp ids(_value, key), do: {:error, %{key => "must be a list of snapshot ids"}}

  @doc "S5: submit (member) or submit + approve + execute (admin). See scheduling.md."
  def submit(conn, %{"plan_id" => plan_id} = params) do
    with {:ok, submit} <- submit_params(params),
         {:ok, outcome} <-
           Scheduling.submit_plan(
             scope(conn),
             mission_id(conn),
             plan_id,
             submit.operation_id,
             submit
           ) do
      respond_submit(conn, plan_id, outcome)
    else
      {:error, reason} -> submit_error(conn, plan_id, reason)
    end
  end

  @doc "Re-executes an approved plan whose execution was interrupted (idempotent per item)."
  def execute(conn, %{"plan_id" => plan_id}) do
    with :ok <- may_execute(conn),
         {:ok, plan} <- ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id),
         true <-
           PlanDetail.effective_state(conn, plan).state in [:interrupted, :approved] or
             :not_resumable,
         {:ok, version, sha} <-
           Scheduling.approved_version(org_id(conn), mission_id(conn), plan_id) do
      start_execution(conn, plan_id, version, sha)
      conn |> put_status(:accepted) |> json(%{data: %{plan_id: plan_id, state: :executing}})
    else
      {:error, :forbidden} -> Problem.respond(conn, :forbidden)
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
      :not_resumable -> Problem.respond(conn, :plan_not_resumable)
      {:error, _reason} -> Problem.respond(conn, :plan_not_resumable)
    end
  end

  defp respond_submit(conn, plan_id, {:execute, version, sha}) do
    start_execution(conn, plan_id, version, sha)

    conn
    |> put_status(:accepted)
    |> json(%{data: %{plan_id: plan_id, state: :executing, outcome: :executing}})
  end

  defp respond_submit(conn, plan_id, outcome) when outcome in [:pending_approval, :replayed] do
    state =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, plan} -> PlanDetail.effective_state(conn, plan).state
        _missing -> nil
      end

    json(conn, %{data: %{plan_id: plan_id, state: state, outcome: outcome}})
  end

  # The capability execution enforces (ContactPlanExecutions: a person needs :operate_mission),
  # checked at the request so a refused caller gets 403, not a 202 and a run that fails later.
  # A service identity's automation grant is still checked by the run itself.
  defp may_execute(conn) do
    case scope(conn) do
      %{actor_kind: :service} ->
        :ok

      scope ->
        Policy.authorize(scope, :operate_mission, %{
          organization_id: scope.organization_id,
          mission_id: mission_id(conn)
        })
    end
  end

  defp start_execution(conn, plan_id, version, sha) do
    scope = scope(conn)
    mission_id = mission_id(conn)

    SchedulingRunner.start(mission_id, :execute, plan_id, fn ->
      Scheduling.execute_plan(scope, mission_id, plan_id, version, sha)
    end)
  end

  defp submit_params(params) do
    with {:ok, version} <- positive(params["expected_version"], :expected_version),
         {:ok, operation_id} <- operation_id(params["operation_id"]),
         {:ok, acknowledgements} <- acknowledgements(params["acknowledgements"]),
         {:ok, note} <- note(params["note"], :note),
         {:ok, decision_note} <- note(params["decision_note"], :decision_note) do
      {:ok,
       %{
         expected_version: version,
         operation_id: operation_id,
         reason: if(is_binary(params["reason"]), do: params["reason"]),
         note: note,
         decision_note: decision_note,
         acknowledgements: acknowledgements
       }}
    end
  end

  # U36: the submitter's optional note for the reviewer ("What changed"); U76: the approver's
  # optional decision_note for the record (an org admin's submit approves). One cap, 2,000
  # characters after trimming, with ux U76's line.
  @note_max 2_000

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

  defp submit_error(conn, _plan_id, {:contact_plan_superseded, superseded}),
    do: Problem.respond(conn, :plan_superseded, ConfigJSON.encode(%{superseded: superseded}))

  defp submit_error(conn, plan_id, :contact_plan_not_satisfied) do
    details =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, plan} -> %{unmet: plan.unmet, conflicts: plan.conflicts}
        _missing -> nil
      end

    Problem.respond(conn, :plan_not_ready, ConfigJSON.encode(details))
  end

  defp submit_error(conn, _plan_id, {:contact_plan_exceptions_required, ids}),
    do: Problem.respond(conn, :acknowledgements_required, %{missing: ids})

  defp submit_error(conn, _plan_id, {:contact_plan_exceptions_unknown, ids}),
    do:
      Problem.respond(conn, :invalid_params, %{
        acknowledgements: "not unmet in this plan: #{Enum.join(ids, ", ")}"
      })

  defp submit_error(conn, _plan_id, {:contact_plan_exception_invalid, id}),
    do:
      Problem.respond(conn, :invalid_params, %{
        acknowledgements: "reason for #{id} must be 10-2000 characters"
      })

  defp submit_error(conn, _plan_id, details) when is_map(details),
    do: Problem.respond(conn, :invalid_params, details)

  defp submit_error(conn, _plan_id, :contact_plan_not_found),
    do: Problem.respond(conn, :plan_not_found)

  defp submit_error(conn, _plan_id, :contact_plan_version_changed),
    do: Problem.respond(conn, :plan_changed)

  defp submit_error(conn, _plan_id, :contact_plan_not_submittable),
    do: Problem.respond(conn, :plan_not_submittable)

  defp submit_error(conn, _plan_id, :operation_already_claimed),
    do: Problem.respond(conn, :operation_conflict)

  defp submit_error(conn, _plan_id, :forbidden), do: Problem.respond(conn, :forbidden)

  # U36: after a send back resubmits as a new version, this only means someone decided the
  # version concurrently; say who (lead's K1 reader: details.decided_by.name).
  defp submit_error(conn, plan_id, :contact_plan_version_already_decided) do
    decided_by =
      case ContactPlanOverview.plan(org_id(conn), mission_id(conn), plan_id) do
        {:ok, %{approval: %{actor: actor}}} -> actor
        _unknown -> nil
      end

    Problem.respond(conn, :contact_plan_version_already_decided, %{decided_by: decided_by})
  end

  defp submit_error(conn, _plan_id, reason) when is_atom(reason),
    do: Problem.respond(conn, reason)

  defp submit_error(conn, _plan_id, _reason), do: Problem.respond(conn, :plan_not_submittable)

  defp positive(value, _key) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(_value, key), do: {:error, %{key => "is required (positive integer)"}}

  defp operation_id(value) when is_binary(value) and byte_size(value) in 1..120, do: {:ok, value}
  defp operation_id(_value), do: {:error, %{operation_id: "is required (1-120 chars)"}}

  defp scope(conn), do: conn.assigns.current_scope

  defp day(nil), do: {:ok, nil}

  defp day(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, %{day: "must be YYYY-MM-DD"}}
    end
  end

  defp state(nil), do: {:ok, nil}

  defp state(value) do
    case Map.fetch(Map.merge(@states, @derived), value) do
      {:ok, state} ->
        {:ok, state}

      :error ->
        {:error,
         %{
           state:
             "must be one of #{@states |> Map.merge(@derived) |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
         }}
    end
  end

  defp version(nil), do: {:ok, nil}

  defp version(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _invalid -> {:error, %{version: "must be a positive integer"}}
    end
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
