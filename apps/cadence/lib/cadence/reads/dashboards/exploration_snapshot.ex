defmodule Cadence.Reads.Dashboards.ExplorationSnapshot do
  @moduledoc "Browser-safe exploration results; adapter metadata never crosses this boundary."
  alias Cadence.Dashboards.{DashboardResolveResult, PlacementFrames, ResolveWarning}

  alias Cadence.Reads.Dashboards.{
    Exploration,
    ExplorationQuery,
    ExplorationRows,
    ExplorationSampleSnapshot,
    Workspace
  }

  @query_states [:point_required, :unsupported_exploration_source, :unsupported_exploration_scope]

  def load(scope, mission, params, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    opts = Keyword.put(opts, :now, now)

    result =
      case Exploration.load(scope, mission, params, opts) do
        {:ok, read} ->
          build(read, now)

        {:error, reason} when reason in @query_states ->
          {:ok, admitted} = ExplorationQuery.admit(params, now)

          {:ok,
           base(scope.organization_id, mission, admitted.query, now)
           |> Map.put(:status, Atom.to_string(reason))}

        _ ->
          {:error, :unavailable}
      end

    with {:ok, model} <- result do
      {:ok, Map.put(model, :origin, origin(scope, mission, model.query))}
    end
  end

  defp origin(scope, mission, %{"source_dashboard_id" => id}) do
    case Workspace.reference(scope, mission, id) do
      {:ok, dashboard} -> %{status: "ready", dashboard: dashboard}
      _ -> %{status: "unavailable", dashboard: nil}
    end
  end

  defp origin(_, _, _), do: %{status: "not_provided", dashboard: nil}

  def build(
        %{request: request, query: query, result: %DashboardResolveResult{} = result} = read,
        now
      ) do
    with true <- request.dashboard_id == result.dashboard_id,
         %PlacementFrames{primary: frames, warnings: warnings} <-
           result.frames_by_placement["exploration"],
         {:ok, rows, limited} <- ExplorationRows.project(frames, request),
         all_warnings = warnings ++ result.dashboard_warnings,
         {:ok, warnings, warnings_limited} <- warnings(all_warnings) do
      status =
        cond do
          rows != [] -> "ready"
          frames != [] and not Enum.any?(all_warnings, &(&1.severity == :error)) -> "empty"
          true -> "unavailable"
        end

      {:ok,
       base(request.organization_id, request.mission_id, query, now)
       |> Map.merge(%{
         status: status,
         rows: rows,
         limited: limited,
         warnings: warnings,
         warnings_limited: warnings_limited,
         inspection:
           ExplorationSampleSnapshot.build(Map.get(read, :selected_sample), query, request),
         effective_time: %{
           mode: request.time_context.mode,
           axis: request.time_context.axis,
           from: timestamp(request.time_context.from),
           to: timestamp(request.time_context.to)
         }
       })}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp base(org, mission, query, now) do
    %{
      version: 3,
      organization_id: org,
      mission_id: mission,
      query: query,
      origin: %{
        status: if(query["source_dashboard_id"], do: "unavailable", else: "not_provided"),
        dashboard: nil
      },
      loaded_at: DateTime.to_iso8601(now),
      status: "unavailable",
      effective_time: nil,
      rows: [],
      limited: false,
      warnings: [],
      warnings_limited: false,
      inspection: ExplorationSampleSnapshot.build(nil, query, nil)
    }
  end

  defp warnings(values) when is_list(values) and length(values) <= 10_000 do
    values
    |> Enum.reduce_while({:ok, []}, fn
      %ResolveWarning{code: code, severity: severity}, {:ok, acc}
      when is_atom(code) and severity in [:info, :warning, :error] ->
        code = Atom.to_string(code)

        if byte_size(code) in 1..128 and Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, code),
          do: {:cont, {:ok, [%{code: code, severity: Atom.to_string(severity)} | acc]}},
          else: {:halt, :error}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, rows} ->
        rows = rows |> Enum.reverse() |> Enum.uniq()
        {:ok, Enum.take(rows, 50), length(rows) > 50}

      _ ->
        :error
    end
  end

  defp warnings(_), do: :error
  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = time), do: DateTime.to_iso8601(time)
end
