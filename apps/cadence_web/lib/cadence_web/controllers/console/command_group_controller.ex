defmodule CadenceWeb.Console.CommandGroupController do
  @moduledoc """
  Command groups (M16 / M18 / M20, O4). Contract: docs/apogee/api/commanding.md.
  The requester, approver and aborting operator are always the session user.
  """

  use CadenceWeb, :controller

  alias Cadence.Commanding.CommandPolicy
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupAbort, GroupDecision, GroupNotes, GroupSubmission}
  alias Cadence.Reads.{CommandEndpoints, CommandGroups, CommandPreflight}
  alias CadenceWeb.Console.{CommandGroupJSON, CommandGroupParams, CommandGroupProblems}

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
         {:ok, acks} <- CommandGroupParams.acknowledged_holds(params),
         {:ok, accepted} <- holds_satisfied(conn, draft, acks, operation_id),
         {:ok, group} <-
           GroupSubmission.submit(conn.assigns.current_scope, mission(conn), draft,
             preflight_digest: params["preflight_digest"],
             operation_id: operation_id,
             hold_acks: accepted
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

  def index(conn, params) do
    groups =
      CommandGroups.list(org(conn), mission(conn), viewer(conn),
        states: states(params["state"]),
        awaiting_me: params["awaiting_me"] == "true",
        mine: params["mine"] == "true"
      )

    json(conn, %{data: %{groups: Enum.map(groups, &CommandGroupJSON.summary/1)}})
  end

  def show(conn, %{"command_group_id" => id}) do
    case CommandGroups.get(org(conn), mission(conn), id, viewer(conn)) do
      {:ok, view} -> json(conn, %{data: CommandGroupJSON.show(view)})
      error -> CommandGroupProblems.respond(conn, error)
    end
  end

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
         {:ok, _group} <-
           GroupDecision.decide(conn.assigns.current_scope, mission(conn), id, decision) do
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

  def endpoints(conn, params) do
    ids =
      case params["spacecraft_ids"] do
        value when is_binary(value) -> value |> String.split(",", trim: true) |> Enum.take(1_000)
        _other -> []
      end

    endpoints = CommandEndpoints.for_spacecraft(org(conn), mission(conn), ids)
    json(conn, %{data: CommandGroupJSON.endpoints(endpoints)})
  end

  def policies(conn, _params) do
    json(conn, %{data: CommandGroupJSON.policies(CommandPolicy.policies())})
  end

  defp states(nil), do: nil

  defp states(value) when is_binary(value) do
    allowed = MapSet.new(~w(approval_pending queued rejected sent_back aborted))
    value |> String.split(",", trim: true) |> Enum.filter(&MapSet.member?(allowed, &1))
  end

  defp states(_value), do: nil

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id

  defp viewer(conn),
    do: conn.assigns.current_scope.user && conn.assigns.current_scope.user.user_id

  defp actor(conn), do: %{"actor_kind" => "user", "user_id" => viewer(conn)}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
