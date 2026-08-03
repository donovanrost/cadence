defmodule CadenceWeb.OpsDashboardShowLive.WidgetBindingPreview do
  @moduledoc false

  alias Cadence.Dashboards.{Document, Field, Frame, Placement, PlacementEditor, PlacementFrames}

  alias CadenceWeb.OpsDashboardShowLive.{
    EngineResolution,
    RuntimeDataRequest,
    RuntimeResult
  }

  @type status :: :ready | :no_data | :error

  @type t :: %{
          status: status(),
          title: binary(),
          message: binary(),
          planned_request_count: non_neg_integer(),
          frame_count: non_neg_integer(),
          warning_count: non_neg_integer()
        }

  @spec run(
          Phoenix.LiveView.Socket.t(),
          map(),
          binary() | [binary()] | nil,
          term(),
          Placement.t() | nil,
          keyword()
        ) :: {:ok, t()} | {:error, binary()}
  def run(socket, params, selected_observables, panel, existing_placement, opts \\ [])
      when is_map(params) do
    authoring_opts = [authoring_scope_context: socket.assigns.dashboard_scope_context]

    case PlacementEditor.build_placement(
           params,
           selected_observables,
           panel,
           existing_placement,
           authoring_opts
         ) do
      {:ok, %Placement{} = placement} ->
        document = Document.replace_placements(socket.assigns.dashboard_document, [placement])

        request =
          socket
          |> RuntimeDataRequest.from_socket(:context_change)
          |> Map.put(:document, document)
          |> Map.put(:document_mode, :draft_preview)

        result = resolve_request_fn(opts).(request)
        {:ok, summarize(result, placement.placement_id)}

      {:error, {_kind, message}} ->
        {:error, message}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @spec summarize(RuntimeResult.result(), binary()) :: t()
  def summarize(result, placement_id) when is_binary(placement_id) do
    placement_frames = RuntimeResult.placement_frames(result, placement_id)
    planned_request_count = result |> RuntimeResult.planned_source_requests() |> length()
    dashboard_warnings = RuntimeResult.dashboard_warnings(result)
    placement_warnings = placement_warnings(placement_frames)
    warning_count = length(dashboard_warnings) + length(placement_warnings)
    primary_frames = primary_frames(placement_frames)
    frame_count = length(primary_frames)

    cond do
      Enum.any?(primary_frames, &frame_has_values?/1) ->
        %{
          status: :ready,
          title: "Binding is producing data",
          message:
            "#{planned_request_label(planned_request_count)} produced #{frame_label(frame_count)} with renderable values.",
          planned_request_count: planned_request_count,
          frame_count: frame_count,
          warning_count: warning_count
        }

      planned_request_count > 0 ->
        %{
          status: :no_data,
          title: "Binding is valid, but empty",
          message:
            "#{planned_request_label(planned_request_count)} completed without renderable values in the current scope and time range.",
          planned_request_count: planned_request_count,
          frame_count: frame_count,
          warning_count: warning_count
        }

      true ->
        %{
          status: :error,
          title: "Binding cannot run",
          message:
            first_warning_message(placement_warnings ++ dashboard_warnings) ||
              "The dashboard engine could not plan a source request for this binding.",
          planned_request_count: 0,
          frame_count: frame_count,
          warning_count: warning_count
        }
    end
  end

  defp primary_frames(%PlacementFrames{primary: frames}) when is_list(frames), do: frames
  defp primary_frames(%{primary: frames}) when is_list(frames), do: frames
  defp primary_frames(%{"primary" => frames}) when is_list(frames), do: frames
  defp primary_frames(_placement_frames), do: []

  defp placement_warnings(%PlacementFrames{warnings: warnings}) when is_list(warnings),
    do: warnings

  defp placement_warnings(%{warnings: warnings}) when is_list(warnings), do: warnings
  defp placement_warnings(%{"warnings" => warnings}) when is_list(warnings), do: warnings
  defp placement_warnings(_placement_frames), do: []

  defp frame_has_values?(%Frame{fields: fields}), do: Enum.any?(fields, &field_has_values?/1)

  defp frame_has_values?(%{fields: fields}) when is_list(fields),
    do: Enum.any?(fields, &field_has_values?/1)

  defp frame_has_values?(_frame), do: false

  defp field_has_values?(%Field{values: values}), do: values != []
  defp field_has_values?(%{values: values}) when is_list(values), do: values != []
  defp field_has_values?(%{"values" => values}) when is_list(values), do: values != []
  defp field_has_values?(_field), do: false

  defp first_warning_message(warnings) do
    Enum.find_value(warnings, fn warning ->
      case get_attr(warning, :message) do
        message when is_binary(message) and message != "" -> message
        _missing -> nil
      end
    end)
  end

  defp planned_request_label(1), do: "1 source request"
  defp planned_request_label(count), do: "#{count} source requests"

  defp frame_label(1), do: "1 primary frame"
  defp frame_label(count), do: "#{count} primary frames"

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp resolve_request_fn(opts),
    do: Keyword.get(opts, :resolve_widget_binding, &EngineResolution.resolve_request/1)
end
