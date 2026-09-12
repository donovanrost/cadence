defmodule Cadence.Reads.Dashboards.WorkspaceSnapshot do
  @moduledoc """
  Versioned browser snapshot of a resolved dashboard, without server presentation.

  This projects the exact hydrated document returned by Resolution. Unknown
  widget definitions and malformed frame buckets remain visible as unavailable
  placements instead of disappearing from the canvas.
  """
  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    DataContext,
    Document,
    LimitContext,
    PlacementExpansion,
    PlacementFrames,
    RenderWidget,
    ScopeContext,
    TimeContext,
    WidgetRegistry
  }

  alias Cadence.Reads.Dashboards.WorkspaceFrame

  def build(
        %Document{} = document,
        %DashboardResolveResult{} = result,
        %DashboardResolveRequest{} = request,
        author
      )
      when is_boolean(author) do
    placements = PlacementExpansion.expand(document, request.scope_context)

    with true <-
           result.dashboard_id == document.dashboard_id and
             request.dashboard_id == document.dashboard_id and
             request.organization_id == document.organization_id and
             request.mission_id == document.mission_id,
         true <- length(placements) <= 1024 and length(document.sections) <= 64,
         true <-
           unique_ids?(placements, :placement_id) and unique_ids?(document.sections, :section_id) do
      {:ok,
       %{
         version: 1,
         organization_id: document.organization_id,
         mission_id: document.mission_id,
         dashboard_id: document.dashboard_id,
         document_version: Document.version(document),
         document_mode: Atom.to_string(request.document_mode),
         author: author,
         name: document.name,
         description: document.description,
         grid: Map.take(document.grid, [:columns, :row_height_px, :gap_px]),
         context: context(document, request),
         sections:
           Enum.map(document.sections, fn section ->
             %{
               id: section.section_id,
               title: section.title,
               description: section.description,
               collapsed: section.collapsed_by_default?
             }
           end),
         placements: Enum.map(placements, &placement(&1, result.frames_by_placement)),
         warnings: warnings(result.dashboard_warnings)
       }}
    else
      _ -> {:error, :invalid_workspace_snapshot}
    end
  end

  defp placement(placement, buckets) do
    base = %{
      id: placement.placement_id,
      authored_id: PlacementExpansion.authored_placement_id(placement.placement_id),
      section_id: placement.section_id,
      layout: Map.take(placement.layout, [:x, :y, :w, :h]),
      widget: nil,
      frames: [],
      annotations: [],
      warnings: []
    }

    with {:ok, widget} <- RenderWidget.from_placement(placement),
         {:ok, _type} <-
           WidgetRegistry.fetch_type(widget.widget_type_id, widget.widget_type_version),
         %PlacementFrames{} = bucket <- Map.get(buckets, placement.placement_id),
         {:ok, frames} <- frames(bucket),
         {:ok, annotations} <- annotations(bucket.annotations) do
      Map.merge(base, %{
        status: "ready",
        reason: nil,
        widget: %{
          type: Atom.to_string(widget.type),
          version: widget.widget_type_version,
          title: widget.title,
          options: widget.options
        },
        frames: frames,
        annotations: annotations,
        warnings: warnings(bucket.warnings)
      })
    else
      {:error, :invalid_frame} ->
        Map.merge(base, %{status: "unavailable", reason: "invalid_frame"})

      {:error, :invalid_annotation} ->
        Map.merge(base, %{status: "unavailable", reason: "invalid_frame"})

      nil ->
        Map.merge(base, %{status: "unavailable", reason: "missing_result"})

      _ ->
        Map.merge(base, %{status: "unavailable", reason: "unsupported_widget"})
    end
  end

  defp annotations(values) when is_list(values) and length(values) <= 1000 do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case WorkspaceFrame.annotation(value) do
        {:ok, annotation} -> {:cont, {:ok, acc ++ [annotation]}}
        error -> {:halt, error}
      end
    end)
  end

  defp annotations(_), do: {:error, :invalid_annotation}

  defp frames(%PlacementFrames{primary: primary, overlays: overlays})
       when is_list(primary) and is_map(overlays) do
    roles = [
      {"primary", primary}
      | Enum.map(overlays, fn {role, values} -> {to_string(role), values} end)
    ]

    if Enum.all?(roles, fn {role, values} ->
         role in ~w(primary compare limits quality events annotations) and is_list(values) and
           length(values) <= 64
       end) do
      project_roles(roles)
    else
      {:error, :invalid_frame}
    end
  end

  defp frames(_), do: {:error, :invalid_frame}

  defp project_roles(roles) do
    Enum.reduce_while(roles, {:ok, []}, fn {role, values}, {:ok, acc} ->
      case project_frames(values, role) do
        {:ok, projected} -> {:cont, {:ok, acc ++ projected}}
        error -> {:halt, error}
      end
    end)
  end

  defp project_frames(values, role) do
    Enum.reduce_while(values, {:ok, []}, fn frame, {:ok, acc} ->
      case WorkspaceFrame.project(frame) do
        {:ok, dto} -> {:cont, {:ok, acc ++ [Map.put(dto, :role, role)]}}
        _ -> {:halt, {:error, :invalid_frame}}
      end
    end)
  end

  defp warnings(warnings) when is_list(warnings) do
    warnings
    |> Enum.map(fn warning ->
      # Raw messages/details may contain endpoint, SQL or adapter exception text.
      %{code: warning_code(warning.code), severity: warning_severity(warning.severity)}
    end)
    |> Enum.uniq()
  end

  defp warning_code(code) when is_atom(code), do: warning_code(Atom.to_string(code))

  defp warning_code(code) when is_binary(code) and byte_size(code) <= 128 do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, code), do: code, else: "unavailable_warning"
  end

  defp warning_code(_), do: "unavailable_warning"

  defp warning_severity(severity) when severity in [:info, :warning, :error],
    do: Atom.to_string(severity)

  defp warning_severity(_), do: "warning"

  defp context(document, request) do
    defaults = document.defaults
    time = TimeContext.resolve(request.time_context, get(defaults, :time), nil)
    data = DataContext.resolve(request.data_context, get(defaults, :data), nil)
    limits = LimitContext.resolve(request.limit_context, get(defaults, :limits), nil)
    scope = ScopeContext.resolve(request.scope_context, get(defaults, :scope), nil)

    %{
      time_mode: text_default(time.mode, :live),
      time_axis: text_default(time.axis, :generation_time),
      from:
        first_bound([
          time.from,
          time.start,
          time.start_time,
          get(time.range, :from),
          get(time.range, :start)
        ]),
      to:
        first_bound([
          time.to,
          time.end,
          time.end_time,
          get(time.range, :to),
          get(time.range, :end)
        ]),
      window_seconds: time.window_seconds,
      relative_duration_ms: get(time.range, :duration_ms),
      refresh_ms: time.refresh_ms,
      realm: text_default(data.realm, :flight),
      data_view: text_default(data.view, :canonical),
      limit_mode: text_default(limits.semantics_mode, :observed),
      scope_kind: text_default(ScopeContext.primary_kind(scope), :mission),
      scope_ids: ScopeContext.primary_ids(scope)
    }
  end

  defp text_default(value, default), do: to_string(value || default)
  defp first_bound(values), do: values |> Enum.find(& &1) |> bound()

  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp get(_, _), do: nil
  defp bound(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp bound(value) when is_binary(value) or is_nil(value), do: value

  defp unique_ids?(values, key) do
    ids = Enum.map(values, &Map.fetch!(&1, key))
    Enum.all?(ids, &(is_binary(&1) and &1 != "")) and length(ids) == length(Enum.uniq(ids))
  end
end
