defmodule CadenceWeb.Console.DashboardAuthoringController do
  @moduledoc """
  Dashboard editing for the console, D7-D13 (owner: api; contract dashboards.md §Authoring),
  stateless on the server: the browser keeps `{base_version, commands}` and sends them each time
  (`Cadence.Dashboards.StatelessAuthoring`, DECISIONS #76). A command is `{event, input}` with
  the legacy draft's events.

  D7 preview, D8 observable choices, D9 save, D10 rebase, D11 copy, D12 versions and compare,
  D13 restore. Editing needs `dashboard.author` (Policy `:author_dashboards`, checked by
  StatelessAuthoring).
  """

  use CadenceWeb, :controller

  alias Cadence.Dashboards.{Document, SaveWarnings, StatelessAuthoring}
  alias Cadence.Reads.Dashboards.{Editor, ObservableChoices, Versions, Workspace}
  alias CadenceWeb.Console.{ConfigJSON, DashboardDefaults, DashboardRuntime, Problem}

  # D7: the staged document resolved with live data paused, its changes and its editable outline.
  def preview(conn, %{"dashboard_id" => id} = params) do
    with {:ok, runtime} <- DashboardRuntime.admit(params["runtime"]),
         {:ok, staged} <-
           StatelessAuthoring.preview(
             scope(conn),
             mission(conn),
             id,
             params["base_version"],
             params["commands"]
           ),
         {:ok, body} <- staged_body(conn, staged.document, runtime) do
      ok(conn, Map.merge(body, %{changes: staged.diff, current_version: staged.current_version}))
    else
      error -> error(conn, id, error)
    end
  end

  # D8: observables a widget can bind, searched as the widget form describes it.
  def observables(conn, %{"dashboard_id" => id} = params) do
    input = %{
      "query" => params["query"] || "",
      "fields" => params["fields"],
      "expected_version" => params["base_version"]
    }

    case ObservableChoices.search(scope(conn), mission(conn), id, input) do
      {:ok, found} ->
        ok(conn, %{
          observables:
            Enum.map(
              found.options,
              &%{id: &1.value, label: &1.label, description: &1.description}
            ),
          more: found.more
        })

      {:error, _unavailable} ->
        Problem.respond(conn, :invalid_params, %{
          fields: "must be the widget's form fields at base_version"
        })
    end
  end

  # D9: replays the commands on base_version and saves them as the next current version.
  def save(conn, %{"dashboard_id" => id} = params) do
    with {:ok, runtime} <- DashboardRuntime.admit(params["runtime"]),
         {:ok, commands} <- with_defaults(conn, id, params, runtime),
         {:ok, saved} <-
           StatelessAuthoring.save(
             scope(conn),
             mission(conn),
             id,
             params["base_version"],
             commands,
             params["message"]
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{version: saved.version, changed: saved.changed, warnings: warnings(saved)}
      })
    else
      error -> error(conn, id, error)
    end
  end

  # D10: the commands replayed on the newest version; the client keeps `applied`.
  def rebase(conn, %{"dashboard_id" => id} = params) do
    commands = params["commands"]

    with {:ok, runtime} <- DashboardRuntime.admit(params["runtime"]),
         {:ok, rebased} <- StatelessAuthoring.rebase(scope(conn), mission(conn), id, commands),
         {:ok, staged} <-
           StatelessAuthoring.preview(
             scope(conn),
             mission(conn),
             id,
             rebased.base_version,
             applied(commands, rebased.applied)
           ),
         {:ok, body} <- staged_body(conn, rebased.document, runtime) do
      ok(
        conn,
        Map.merge(body, %{
          base_version: rebased.base_version,
          applied: applied(commands, rebased.applied),
          skipped:
            Enum.map(rebased.skipped, &%{index: &1.index, event: &1.event, reason: &1.code}),
          changes: staged.diff,
          current_version: staged.current_version
        })
      )
    else
      error -> error(conn, id, error)
    end
  end

  # D11: the staged document (base_version plus commands) as a new dashboard.
  def copy(conn, %{"dashboard_id" => id} = params) do
    case StatelessAuthoring.copy(
           scope(conn),
           mission(conn),
           id,
           params["base_version"],
           params["commands"] || [],
           %{"name" => params["name"]}
         ) do
      {:ok, %Document{} = copy} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            id: copy.dashboard_id,
            version: Document.version(copy),
            warnings: SaveWarnings.for_document(copy)
          }
        })

      error ->
        error(conn, id, error)
    end
  end

  # D12: versions newest first, and which one is current (a legacy dashboard may have none).
  def versions(conn, %{"dashboard_id" => id}) do
    case StatelessAuthoring.versions(scope(conn), mission(conn), id) do
      {:ok, rows} ->
        ok(conn, %{
          current_version: Enum.find_value(rows, &(&1.current && &1.version)),
          versions: Enum.map(rows, &version_row/1)
        })

      error ->
        error(conn, id, error)
    end
  end

  def compare(conn, %{"dashboard_id" => id} = params) do
    with {:ok, from} <- version_param(params["from"]),
         {:ok, to} <- version_param(params["to"]),
         {:ok, comparison} <- Versions.compare(scope(conn), mission(conn), id, from, to) do
      ok(conn, Map.take(comparison, [:from, :to, :changes, :from_json, :to_json]))
    else
      {:error, :invalid_version} ->
        Problem.respond(conn, :invalid_params, %{from: "and to must be two different versions"})

      {:error, _unavailable} ->
        Problem.respond(conn, :not_found)
    end
  end

  # D13: a saved version becomes the next current version.
  def restore(conn, %{"dashboard_id" => id, "version" => version} = params) do
    with {:ok, version} <- version_param(version),
         {:ok, %Document{} = restored} <-
           StatelessAuthoring.restore(
             scope(conn),
             mission(conn),
             id,
             version,
             params["expected_version"]
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          version: Document.version(restored),
          warnings: SaveWarnings.for_document(restored)
        }
      })
    else
      error -> error(conn, id, error)
    end
  end

  defp staged_body(conn, document, runtime) do
    case Workspace.preview(scope(conn), document, runtime: runtime) do
      {:ok, snapshot} -> {:ok, %{snapshot: snapshot, outline: Editor.outline(document)}}
      {:error, :invalid_scope} -> {:error, :invalid_scope}
      {:error, _unavailable} -> {:error, :unavailable}
    end
  end

  # "Save the current range and scope as the default" is one more command on the staged document.
  defp with_defaults(conn, id, %{"defaults" => %{} = flags} = params, runtime) do
    commands = params["commands"]

    with {:ok, staged} <-
           StatelessAuthoring.preview(
             scope(conn),
             mission(conn),
             id,
             params["base_version"],
             commands
           ) do
      case DashboardDefaults.command(staged.document, runtime, flags) do
        {:ok, command} -> {:ok, commands ++ [command]}
        :none -> {:ok, commands}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp with_defaults(_conn, _id, params, _runtime), do: {:ok, params["commands"]}

  defp applied(commands, indexes) when is_list(commands),
    do: Enum.map(indexes, &Enum.at(commands, &1))

  defp version_row(row) do
    %{
      version: row.version,
      kind: row.kind,
      based_on_version: row.based_on_version,
      saved_by:
        row.created_by && %{kind: "user", id: row.created_by.id, name: row.created_by.name},
      saved_at: row.created_at,
      message: row.change_summary,
      current: row.current
    }
  end

  defp version_param(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp version_param(n) when is_binary(n) do
    case Integer.parse(n) do
      {v, ""} when v > 0 -> {:ok, v}
      _invalid -> {:error, :invalid_version}
    end
  end

  defp version_param(_n), do: {:error, :invalid_version}

  defp error(conn, _id, {:error, {:command, index, code, field}}),
    do: Problem.respond(conn, :invalid_command, %{index: index, code: code, field: field})

  defp error(conn, id, {:error, {:conflict, current}}),
    do: Problem.respond(conn, :version_conflict, conflict(conn, id, current))

  defp error(conn, id, {:error, :conflict}),
    do: Problem.respond(conn, :version_conflict, conflict(conn, id, nil))

  defp error(conn, _id, {:error, :too_many_commands}),
    do: Problem.respond(conn, :too_many_commands)

  defp error(conn, _id, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)
  defp error(conn, _id, {:error, :not_found}), do: Problem.respond(conn, :not_found)

  defp error(conn, _id, {:error, :invalid_range}),
    do: Problem.respond(conn, :invalid_params, %{field: "range"})

  defp error(conn, _id, {:error, :invalid_scope}),
    do: Problem.respond(conn, :invalid_params, %{field: "spacecraft_id"})

  defp error(conn, _id, {:error, :invalid_version}),
    do: Problem.respond(conn, :invalid_params, %{version: "must be a positive integer"})

  defp error(conn, _id, {:error, {:not_ready, issues}}),
    do: Problem.respond(conn, :dashboard_not_ready, %{placements: issues})

  defp error(conn, _id, {:error, :invalid_document}),
    do: Problem.respond(conn, :dashboard_not_ready, %{placements: []})

  defp error(conn, _id, {:error, :invalid_defaults}),
    do:
      Problem.respond(conn, :invalid_params, %{
        defaults: "can't be saved from this range or scope"
      })

  defp error(conn, _id, {:error, :invalid_input}), do: Problem.respond(conn, :invalid_params)
  defp error(conn, _id, _unavailable), do: Problem.respond(conn, :dashboard_unavailable)

  # Who saved over you and when, from the newest version (D9's callout).
  defp conflict(conn, id, current) do
    newest =
      case StatelessAuthoring.versions(scope(conn), mission(conn), id) do
        {:ok, [row | _]} -> row
        _none -> nil
      end

    %{
      current_version: current || (newest && newest.version),
      saved_by:
        newest && newest.created_by &&
          %{kind: "user", id: newest.created_by.id, name: newest.created_by.name},
      saved_at: newest && newest.created_at
    }
  end

  # lead 11-14: sources a read reported unavailable no longer block a save; the save sheet says
  # so. An unchanged save re-checked nothing.
  defp warnings(%{changed: true, document: document}), do: SaveWarnings.for_document(document)
  defp warnings(_unchanged), do: []

  defp ok(conn, data), do: json(conn, %{data: ConfigJSON.encode(data)})
  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
