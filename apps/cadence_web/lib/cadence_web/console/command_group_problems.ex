defmodule CadenceWeb.Console.CommandGroupProblems do
  @moduledoc "Maps command-group errors to console problem responses. Contract: docs/apogee/api/commanding.md."

  alias CadenceWeb.Console.Problem

  @plain ~w(preflight_stale title_required log_entry_required command_group_not_found
            command_group_not_pending command_group_self_approval_not_allowed
            not_the_requested_approver command_group_review_stale command_group_basis_changed
            note_required exclusions_required unknown_excluded_target invalid_decision
            command_group_not_abortable reason_required command_request_already_started
            command_request_not_found)a

  @spec respond(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def respond(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  def respond(conn, {:error, reason}) when reason in @plain, do: Problem.respond(conn, reason)
  def respond(conn, {:error, :unavailable}), do: Problem.respond(conn, :forbidden)

  def respond(conn, {:error, {:duplicate_operation, id}}),
    do: Problem.respond(conn, :duplicate_operation, %{command_group_id: id})

  def respond(conn, {:error, {:holds_unacknowledged, holds}}),
    do: Problem.respond(conn, :holds_unacknowledged, %{holds: holds})

  def respond(conn, {:error, {:preflight_no_go, failures}}),
    do: Problem.respond(conn, :preflight_no_go, failures_details(failures))

  def respond(conn, {:error, {:command_group_too_large, evidence}}),
    do: Problem.respond(conn, :command_group_too_large, evidence)

  def respond(conn, {:error, {:command_group_members_changed, submitted, current}}),
    do:
      Problem.respond(conn, :command_group_members_changed, %{
        submitted_member_count: submitted,
        current_member_count: current
      })

  def respond(conn, {:error, {:command_catalog_not_active, _reason}}),
    do: Problem.respond(conn, :command_catalog_not_active)

  def respond(conn, _error), do: Problem.respond(conn, :commanding_unavailable)

  defp failures_details(failures) do
    %{
      identity:
        Enum.map(Map.get(failures, :identity_failures, []), fn failure ->
          %{
            spacecraft_id: failure.spacecraft_id,
            reason: to_string(failure.failure),
            routes: Map.get(failure, :failure_detail, [])
          }
        end),
      catalog:
        Enum.map(Map.get(failures, :catalog_failures, []), fn failure ->
          %{
            spacecraft_id: failure.spacecraft_id,
            position: failure.position,
            command_id: failure.command_id,
            reason: reason_text(failure.reason)
          }
        end)
    }
  end

  defp reason_text({key, _detail}) when is_atom(key), do: Atom.to_string(key)
  defp reason_text(key) when is_atom(key), do: Atom.to_string(key)
  defp reason_text(_other), do: "invalid"
end
