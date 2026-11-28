defmodule CadenceWeb.Console.CommandGroupController do
  @moduledoc """
  Command groups (M16 / M18 / M20, O4). Contract: docs/apogee/api/commanding.md.
  The requester, approver and aborting operator are always the session user.
  """

  use CadenceWeb, :controller

  alias Cadence.Commanding.CommandPolicy
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupAbort, GroupDecision, GroupNotes, GroupSubmission}

  alias Cadence.Reads.CommandGroups.Page

  alias Cadence.Reads.{
    CommandEndpoints,
    CommandGroups,
    CommandPreflight,
    PassUplink,
    VerifierSeries
  }

  alias CadenceWeb.Console.{
    CommandGroupJSON,
    CommandGroupListParams,
    CommandGroupParams,
    CommandGroupProblems
  }

  def preflight(conn, params) do
    with {:ok, draft} <- CommandGroupParams.draft(params),
         {:ok, preflight} <- CommandPreflight.run(org(conn), mission(conn), actor(conn), draft) do
      json(conn, %{data: CommandGroupJSON.preflight(preflight)})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  def create(conn, params) do
    operation_id = blank_to_nil(params["operation_id"])

    with {:ok, draft} <- CommandGroupParams.draft(params),
         {:ok, draft_revision} <- CommandGroupParams.draft_revision(params),
         {:ok, acks} <- CommandGroupParams.acknowledged_holds(params),
         {:ok, accepted} <- holds_satisfied(conn, draft, acks, operation_id),
         {:ok, group} <-
           GroupSubmission.submit(conn.assigns.current_scope, mission(conn), draft,
             preflight_digest: params["preflight_digest"],
             operation_id: operation_id,
             hold_acks: accepted,
             draft_revision: draft_revision
           ),
         {:ok, view} <-
           CommandGroups.get(org(conn), mission(conn), group.command_group_id, viewer(conn)) do
      conn |> put_status(:created) |> json(%{data: CommandGroupJSON.show(view)})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  # DECISIONS #60: HOLDs hold. Every HOLD in the current preflight is either acknowledged (key and
  # hold_basis match, with a note) or refuses the submit. A replay of a known operation skips this,
  # so it still answers 409 duplicate_operation (U20).
  defp holds_satisfied(conn, draft, acks, operation_id) do
    with :new <- replay(conn, operation_id),
         {:ok, preflight} <- CommandPreflight.run(org(conn), mission(conn), actor(conn), draft) do
      case CommandPreflight.holds(preflight, acks) do
        %{unsatisfied: [], accepted: accepted} ->
          {:ok, Enum.map(accepted, &Map.put(&1, :preflight_digest, preflight.digest))}

        %{unsatisfied: holds} ->
          {:error, {:holds_unacknowledged, holds}}
      end
    else
      :replay -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  # DECISIONS #61: a GO re-runs the review preflight. Hard HOLDs refuse. An ackable HOLD carries the
  # submitter's acknowledgement while its basis is unchanged; a new or changed one needs the
  # approver's own (returned here to be recorded as the approver's event).
  defp go_holds_satisfied(conn, id, %{kind: kind}, acks) when kind in [:go, :go_excluding] do
    with {:ok, %{state: :approval_pending} = group} <-
           GroupStore.fetch(org(conn), mission(conn), id),
         {:ok, preflight} <- CommandPreflight.review(org(conn), mission(conn), group) do
      carried =
        for %{kind: :hold_acknowledged, payload: payload} <-
              GroupStore.events(mission(conn), id),
            do: %{key: payload["key"], hold_basis: payload["hold_basis"], carried: true}

      case CommandPreflight.holds(preflight, carried ++ acks) do
        %{unsatisfied: [], accepted: accepted} ->
          {:ok,
           accepted
           |> Enum.reject(&Map.get(&1, :carried))
           |> Enum.map(&Map.put(&1, :preflight_digest, preflight.digest))}

        %{unsatisfied: holds} ->
          {:error, {:holds_unacknowledged, holds}}
      end
    else
      # Not pending (or gone): the decision itself answers.
      {:ok, _decided} -> {:ok, []}
      {:error, :command_group_not_found} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp go_holds_satisfied(_conn, _id, _decision, _acks), do: {:ok, []}

  defp replay(_conn, nil), do: :new

  defp replay(conn, operation_id) do
    case CommandGroups.fetch_by_operation(org(conn), mission(conn), operation_id) do
      {:ok, _group} -> :replay
      {:error, _none} -> :new
    end
  end

  def index(conn, %{"operation_id" => operation_id}) when is_binary(operation_id) do
    case CommandGroups.fetch_by_operation(org(conn), mission(conn), operation_id) do
      {:ok, group} -> json(conn, %{data: %{groups: [CommandGroupJSON.summary(group)]}})
      {:error, :command_group_not_found} -> json(conn, %{data: %{groups: []}})
    end
  end

  # U69 A5: searched (q, target, stage), filtered in SQL and paged by cursor.
  def index(conn, params) do
    with {:ok, opts} <- CommandGroupListParams.parse(params),
         {:ok, page} <- CommandGroups.page(org(conn), mission(conn), viewer(conn), opts) do
      groups = with_uplink(conn, page.groups)

      json(conn, %{
        data: %{groups: Enum.map(groups, &CommandGroupJSON.summary/1)},
        meta: %{next_cursor: page.next_cursor}
      })
    else
      {:error, :invalid_cursor} ->
        CommandGroupProblems.respond(
          conn,
          {:error, {:invalid_params, %{cursor: "is not a valid cursor"}}}
        )

      error ->
        CommandGroupProblems.respond(conn, error)
    end
  end

  def show(conn, %{"command_group_id" => id}) do
    case CommandGroups.get(org(conn), mission(conn), id, viewer(conn)) do
      {:ok, view} ->
        [view] = with_uplink(conn, [view])
        json(conn, %{data: CommandGroupJSON.show(view)})

      error ->
        CommandGroupProblems.respond(conn, error)
    end
  end

  # #795: a group's targets and its events, a page at a time, under show's own authorization.
  # `stage` and `q` filter the targets; a cursor of another group, mission or list is a 422.
  def targets(conn, %{"command_group_id" => id} = params) do
    with {:ok, view} <- CommandGroups.get(org(conn), mission(conn), id, viewer(conn)),
         {:ok, page} <- Page.targets(view, params) do
      json(conn, %{
        data: %{targets: CommandGroupJSON.targets(page.targets)},
        meta: %{total: page.total, next_cursor: page.next_cursor}
      })
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  def events(conn, %{"command_group_id" => id} = params) do
    with {:ok, view} <- CommandGroups.get(org(conn), mission(conn), id, viewer(conn)),
         {:ok, page} <- Page.events(view, params) do
      json(conn, %{
        data: %{events: CommandGroupJSON.events(page.events)},
        meta: %{total: page.total, next_cursor: page.next_cursor}
      })
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  # U33: the pass a queued, unfinished group releases on, with its live uplink readiness.
  defp with_uplink(conn, groups) do
    waiting = for %{state: :queued, finished: false, id: id} <- groups, do: id
    uplink = PassUplink.for_groups(org(conn), mission(conn), waiting)
    Enum.map(groups, &Map.put(&1, :uplink, Map.get(uplink, &1.id)))
  end

  @doc "M26: what Uplink U2 plots. `?targets=` (comma list of spacecraft ids) picks up to 100."
  def verifier_series(conn, %{"command_group_id" => id} = params) do
    case VerifierSeries.load(org(conn), mission(conn), id,
           target_ids: target_ids(params["targets"]),
           # U2: plot this point (one of points[]); else the first.
           point: point_param(params["point"])
         ) do
      {:ok, series} -> json(conn, %{data: CommandGroupJSON.verifier_series(series)})
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  defp target_ids(value) when is_binary(value) and value != "",
    do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp target_ids(_value), do: nil

  defp point_param(value) when is_binary(value) and value != "", do: String.trim(value)
  defp point_param(_value), do: nil

  def review_preflight(conn, %{"command_group_id" => id}) do
    with {:ok, group} <- GroupStore.fetch(org(conn), mission(conn), id),
         {:ok, preflight} <- CommandPreflight.review(org(conn), mission(conn), group) do
      json(conn, %{data: CommandGroupJSON.preflight(preflight)})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  def decision(conn, %{"command_group_id" => id} = params) do
    with {:ok, decision} <- CommandGroupParams.decision(params),
         {:ok, acks} <- CommandGroupParams.acknowledged_holds(params),
         {:ok, hold_acks} <- go_holds_satisfied(conn, id, decision, acks),
         {:ok, _group} <-
           GroupDecision.decide(
             conn.assigns.current_scope,
             mission(conn),
             id,
             Map.put(decision, :hold_acks, hold_acks)
           ) do
      show(conn, %{"command_group_id" => id})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  def abort(conn, %{"command_group_id" => id} = params) do
    with {:ok, reason} <- CommandGroupParams.note(params, "reason"),
         {:ok, _group} <- GroupAbort.abort(conn.assigns.current_scope, mission(conn), id, reason) do
      show(conn, %{"command_group_id" => id})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  def add_note(conn, %{"command_group_id" => id} = params) do
    with {:ok, note} <- CommandGroupParams.note(params, "note"),
         :ok <- GroupNotes.add(conn.assigns.current_scope, mission(conn), id, note) do
      show(conn, %{"command_group_id" => id})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  def cancel_request(conn, %{"command_request_id" => id} = params) do
    with {:ok, reason} <- CommandGroupParams.note(params, "reason"),
         {:ok, result} <-
           GroupAbort.cancel_request(conn.assigns.current_scope, mission(conn), id, reason) do
      json(conn, %{data: %{command_request_id: result.command_request_id, state: "canceled"}})
    else
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

  # POST with `spacecraft_ids` in the body: a fleet's ids don't fit in a URL. (The GET with a
  # comma list stays until the console moves off it.) More ids than the size guard is a 422 naming
  # the bound, never a silent cut.
  def endpoints(conn, params) do
    case CommandGroupParams.spacecraft_ids(params) do
      {:ok, ids} ->
        endpoints = CommandEndpoints.for_spacecraft(org(conn), mission(conn), ids)
        json(conn, %{data: CommandGroupJSON.endpoints(endpoints)})

      error ->
        CommandGroupProblems.respond(conn, error)
    end
  end

  def policies(conn, _params) do
    json(conn, %{data: CommandGroupJSON.policies(CommandPolicy.policies())})
  end

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id

  defp viewer(conn),
    do: conn.assigns.current_scope.user && conn.assigns.current_scope.user.user_id

  defp actor(conn), do: %{"actor_kind" => "user", "user_id" => viewer(conn)}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
