defmodule Cadence.Reads.CommandMonitor do
  @moduledoc """
  Authorized, read-only command monitoring independent of frontend delivery.

  The database returns a bounded page, independent focus and verifier previews
  from one statement snapshot. Aggregate work inside PostgreSQL remains mission-wide.
  No arguments, encoded commands, criteria, secrets or arbitrary metadata cross
  this projection. Reads do not approve, enqueue, release or verify commands.
  """
  alias Cadence.Auth.Scope
  alias Cadence.Management.Commanding.RequestReview
  alias Cadence.Reads.CommandMonitor.Store
  alias Cadence.Reads.CommandMonitorProjection
  alias Cadence.Reads.CommandReadAccess

  @keys ~w(status target query focus_command_id page)
  @page_size 25

  def load(scope, mission, params \\ %{}, opts \\ [])

  def load(%Scope{} = scope, mission, params, opts) when is_list(opts) do
    with :ok <- CommandReadAccess.authorize(scope, mission),
         {:ok, query} <- admit_query(params) do
      snapshot = Store.load(scope.organization_id, mission, query, opts)
      total = snapshot.total
      page = snapshot.page
      project = &CommandMonitorProjection.row(&1, scope.organization_id, mission)
      rows = Enum.map(snapshot.rows, project)
      observed_at = Keyword.get(opts, :observed_at, &DateTime.utc_now/0).()

      model = %{
        version: 1,
        can_review: match?({:ok, _, _}, RequestReview.authorize(scope, mission)),
        organization_id: scope.organization_id,
        mission_id: mission,
        observed_at: CommandMonitorProjection.time(observed_at),
        query: Map.put(query, "page", to_string(page)),
        status: if(total == 0, do: "empty", else: "ready"),
        summary: snapshot.summary,
        total: total,
        pages: snapshot.pages,
        page_size: @page_size,
        targets: snapshot.targets,
        targets_limited: snapshot.targets_limited,
        rows: rows,
        focus: focus(snapshot.focus, query["focus_command_id"], project)
      }

      if byte_size(Jason.encode!(model)) <= 524_288,
        do: {:ok, model},
        else: {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def load(_, _, _, _), do: {:error, :unavailable}

  def admit_query(params) when is_map(params) and map_size(params) <= 5 do
    with true <- Enum.all?(params, fn {key, value} -> key in @keys and query_text?(value) end),
         status = blank_default(params["status"], "all"),
         true <- status == "all" or status in CommandMonitorProjection.statuses(),
         {page, ""} when page in 1..1_000_000 <- Integer.parse(Map.get(params, "page", "1")),
         true <- is_nil(params["focus_command_id"]) or params["focus_command_id"] != "" do
      query = %{
        "status" => status,
        "target" => blank_default(params["target"], "all"),
        "query" => String.trim(Map.get(params, "query", "")),
        "page" => to_string(page)
      }

      {:ok,
       if(params["focus_command_id"],
         do: Map.put(query, "focus_command_id", params["focus_command_id"]),
         else: query
       )}
    else
      _ -> {:error, :invalid_command_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_command_query}

  defp query_text?(value),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) <= 256 and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)

  defp blank_default(value, default) when value in [nil, ""], do: default
  defp blank_default(value, _), do: value
  defp focus(_, nil, _), do: %{status: "not_selected", row: nil}

  defp focus(nil, _, _), do: %{status: "not_found", row: nil}
  defp focus(row, _, project), do: %{status: "ready", row: project.(row)}
end
