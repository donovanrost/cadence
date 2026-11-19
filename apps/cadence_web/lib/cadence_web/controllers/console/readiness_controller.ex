defmodule CadenceWeb.Console.ReadinessController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/readiness`. Contract: docs/apogee/api/setup.md."

  use CadenceWeb, :controller

  alias Cadence.Accounts
  alias Cadence.Control.Configuration
  alias Cadence.Reads.Readiness
  alias CadenceWeb.Console.Problem

  def show(conn, _params) do
    case Readiness.mission(conn.assigns.current_scope, conn.assigns.current_mission.mission_id) do
      {:ok, readiness} ->
        json(conn, %{
          data: %{
            evaluated_at: readiness.evaluated_at,
            verdict: readiness.verdict,
            areas: readiness.areas,
            findings: Enum.map(readiness.findings, &Map.delete(&1, :area)),
            recent_changes: recent_changes(conn)
          }
        })

      {:error, _reason} ->
        Problem.respond(conn, :mission_not_found)
    end
  end

  # R2: the mission's last five configuration revisions, newest first (the change-set ledger is
  # the unified change feed). Empty list when nothing has been applied yet.
  defp recent_changes(conn) do
    case Configuration.list_revisions(
           conn.assigns.current_scope,
           conn.assigns.current_mission.mission_id,
           limit: 5
         ) do
      {:ok, revisions} -> Enum.map(revisions, &change/1)
      {:error, _reason} -> nil
    end
  end

  defp change(revision),
    do: %{
      at: revision.applied_at,
      kind: revision.kind,
      version_label: "r#{revision.revision}",
      summary: revision.summary,
      actor: actor(revision.applied_by)
    }

  defp actor(%{name: name}) when is_binary(name), do: %{name: name}

  defp actor(%{kind: "user", id: id}) when is_binary(id) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> %{name: user.display_name || user.email}
      _missing -> nil
    end
  end

  defp actor(%{kind: "system"}), do: %{name: "Cadence"}
  defp actor(_none), do: nil
end
