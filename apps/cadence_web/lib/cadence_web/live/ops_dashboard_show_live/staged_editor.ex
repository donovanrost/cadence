defmodule CadenceWeb.OpsDashboardShowLive.StagedEditor do
  @moduledoc """
  One in-memory dashboard edit transaction.

  Candidate document changes are rendered through the normal dashboard engine,
  but persistence is deferred until `save/2`. The starting document version is
  the optimistic concurrency token for the complete transaction.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Cadence.Dashboards.{Document, Management, Placement, PlacementEditor, WidgetDef}
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.Runtime

  @spec activate(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def activate(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: loaded_document} =
      socket.assigns

    case Cadence.Dashboards.fetch_document_for_mode(
           scope.organization_id,
           mission.mission_id,
           loaded_document.dashboard_id,
           :edit
         ) do
      {:ok, %Document{} = document} ->
        socket
        |> DocumentLifecycle.assign_document(document, :draft)
        |> assign(:edit_mode?, true)
        |> assign(:editor_route?, true)
        |> assign(:editor_starting_document, document)
        |> assign(:editor_starting_version, Document.version(document))
        |> assign(:editor_dirty?, false)
        |> assign(:editor_change_summaries, [])
        |> assign(:editor_conflict, nil)
        |> assign(:editor_external_candidate_fingerprint, nil)
        |> assign(:panel, nil)
        |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
        |> Runtime.resolve_engine(:context_change, reason: :editor_opened)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to open Dashboard Editor: #{inspect(reason)}")
        |> push_navigate(to: dashboard_path(socket))
    end
  end

  @spec maybe_stage_explore_candidate(Phoenix.LiveView.Socket.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  def maybe_stage_explore_candidate(socket, %{"candidate_source" => "explore"} = params) do
    fingerprint = candidate_fingerprint(params)

    if socket.assigns[:editor_external_candidate_fingerprint] == fingerprint do
      socket
    else
      socket = assign(socket, :editor_external_candidate_fingerprint, fingerprint)

      with point_id when is_binary(point_id) <- text_param(params["candidate_point_id"]),
           {:ok, %Placement{} = placement} <- build_explore_placement(params, point_id),
           document <- Document.put_placement(socket.assigns.dashboard_document, placement),
           {:ok, socket} <-
             stage(socket, document, change_summary: "Added #{point_id} from Explore") do
        socket
        |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
        |> Runtime.resolve_engine(:context_change, reason: :explore_candidate_staged)
        |> put_flash(
          :info,
          "Staged #{point_id} from Explore. Save to create a dashboard version."
        )
      else
        nil ->
          put_flash(socket, :error, "Explore did not provide a telemetry point to stage.")

        {:error, {_kind, message}} ->
          put_flash(socket, :error, "Could not stage the Explore candidate: #{message}")
      end
    end
  end

  def maybe_stage_explore_candidate(socket, %{"candidate_source" => "library"} = params) do
    fingerprint = candidate_fingerprint(params)

    if socket.assigns[:editor_external_candidate_fingerprint] == fingerprint do
      socket
    else
      socket = assign(socket, :editor_external_candidate_fingerprint, fingerprint)
      %{current_scope: scope, current_mission: mission} = socket.assigns

      with item_id when is_binary(item_id) <- text_param(params["candidate_library_item_id"]),
           {version, ""} <- Integer.parse(params["candidate_library_version"] || ""),
           {:ok, library_version} <-
             Management.fetch_library_version(
               scope.organization_id,
               mission.mission_id,
               item_id,
               version
             ),
           placement <-
             build_library_placement(item_id, version, library_version.widget_definition),
           document <- Document.put_placement(socket.assigns.dashboard_document, placement),
           {:ok, socket} <-
             stage(socket, document, change_summary: "Added library item #{item_id} v#{version}") do
        socket
        |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
        |> Runtime.resolve_engine(:context_change, reason: :library_candidate_staged)
        |> put_flash(
          :info,
          "Staged library version #{version}. Save to create a dashboard version."
        )
      else
        _invalid -> put_flash(socket, :error, "Could not stage the selected library version.")
      end
    end
  end

  def maybe_stage_explore_candidate(socket, _params), do: socket

  @spec stage(Phoenix.LiveView.Socket.t(), Document.t(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def stage(socket, %Document{} = document, opts) when is_list(opts) do
    summary = Keyword.get(opts, :change_summary, "Updated dashboard")

    socket =
      socket
      |> DocumentLifecycle.assign_document(document, :draft)
      |> assign(
        :editor_dirty?,
        editor_changed?(socket.assigns.editor_starting_document, document)
      )
      |> assign(
        :editor_change_summaries,
        append_change_summary(socket.assigns.editor_change_summaries, summary)
      )
      |> assign(:editor_conflict, nil)

    {:ok, socket}
  end

  @spec save(Phoenix.LiveView.Socket.t(), keyword()) :: Phoenix.LiveView.Socket.t()
  def save(socket, opts \\ []) do
    if socket.assigns.editor_dirty? do
      persist_candidate(socket, opts)
    else
      finish_save(socket, socket.assigns.dashboard_document, opts)
    end
  end

  @spec discard(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def discard(socket) do
    push_navigate(socket, to: dashboard_path(socket))
  end

  @spec reload(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reload(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case Cadence.Dashboards.fetch_document_for_mode(
           scope.organization_id,
           mission.mission_id,
           document.dashboard_id,
           :edit
         ) do
      {:ok, %Document{} = latest} ->
        socket
        |> DocumentLifecycle.assign_document(latest, :draft)
        |> assign(:editor_starting_document, latest)
        |> assign(:editor_starting_version, Document.version(latest))
        |> assign(:editor_dirty?, false)
        |> assign(:editor_change_summaries, [])
        |> assign(:editor_conflict, nil)
        |> assign(:editor_external_candidate_fingerprint, nil)
        |> assign(:panel, nil)
        |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
        |> Runtime.resolve_engine(:context_change, reason: :editor_reloaded)
        |> put_flash(:info, "Reloaded the latest dashboard draft.")

      {:error, reason} ->
        put_flash(socket, :error, "Failed to reload dashboard: #{inspect(reason)}")
    end
  end

  defp persist_candidate(socket, opts) do
    %{current_scope: scope, current_mission: mission, dashboard_document: candidate} =
      socket.assigns

    case Cadence.Dashboards.update_document(
           scope.organization_id,
           mission.mission_id,
           candidate.dashboard_id,
           candidate,
           expected_version: socket.assigns.editor_starting_version,
           created_by: current_user_id(scope),
           change_summary: semantic_summary(socket.assigns.editor_change_summaries)
         ) do
      {:ok, %Document{} = persisted} ->
        socket
        |> DocumentLifecycle.assign_document(persisted, :draft)
        |> DocumentLifecycle.assign_versions()
        |> DocumentLifecycle.assign_publish_validation()
        |> assign(:editor_starting_document, persisted)
        |> assign(:editor_starting_version, Document.version(persisted))
        |> assign(:editor_dirty?, false)
        |> assign(:editor_change_summaries, [])
        |> assign(:editor_conflict, nil)
        |> put_flash(:info, "Dashboard draft saved as version #{Document.version(persisted)}.")
        |> finish_save(persisted, opts)

      {:error, {:dashboard_version_conflict, current_version}} ->
        socket
        |> assign(:editor_conflict, %{
          starting_version: socket.assigns.editor_starting_version,
          current_version: current_version
        })
        |> put_flash(
          :error,
          "Dashboard changed in another session. Your staged changes were not overwritten."
        )

      {:error, reason} ->
        put_flash(socket, :error, "Failed to save dashboard draft: #{inspect(reason)}")
    end
  end

  defp finish_save(socket, %Document{} = document, opts) do
    if Keyword.get(opts, :review?, false) do
      push_navigate(socket,
        to:
          "/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards/#{document.dashboard_id}/activity?version=#{Document.version(document)}"
      )
    else
      socket
    end
  end

  defp semantic_summary([]), do: "Updated dashboard"
  defp semantic_summary(summaries), do: Enum.join(summaries, "; ")

  defp append_change_summary(summaries, summary) do
    summaries
    |> Kernel.++([summary])
    |> Enum.uniq()
  end

  defp editor_changed?(%Document{} = starting, %Document{} = candidate) do
    Document.to_map(starting) != Document.to_map(candidate)
  end

  defp build_explore_placement(params, point_id) do
    placement_params =
      PlacementEditor.form_defaults()
      |> Map.merge(%{
        "type" => candidate_widget_type(params["candidate_widget_type"]),
        "title" => text_param(params["candidate_title"]) || default_title(point_id),
        "mode" => candidate_mode(params["candidate_spacecraft_id"]),
        "spacecraft_id" => text_param(params["candidate_spacecraft_id"]) || "",
        "binding_source" => "telemetry"
      })

    case PlacementEditor.build_placement(placement_params, [point_id], :add_widget) do
      {:ok, %Placement{} = placement} ->
        {:ok, %Placement{placement | data_override: candidate_data_override(params)}}

      {:error, _reason} = error ->
        error
    end
  end

  defp candidate_data_override(params) do
    source_context =
      %{
        data_source_id: text_param(params["candidate_data_source_id"]),
        source_binding_id: text_param(params["candidate_source_binding_id"])
      }
      |> compact_map()

    %{
      realm: text_param(params["candidate_realm"]),
      view: candidate_data_view(params["candidate_data_view"]),
      source_contexts:
        if(map_size(source_context) == 0, do: nil, else: %{telemetry: source_context})
    }
    |> compact_map()
    |> case do
      override when map_size(override) == 0 -> nil
      override -> override
    end
  end

  defp candidate_widget_type(value) when value in ["value_tile", "time_series"], do: value
  defp candidate_widget_type(_value), do: "time_series"

  defp candidate_data_view(value)
       when value in ["canonical", "all_revisions", "as_recorded", "recomputed"],
       do: value

  defp candidate_data_view(_value), do: nil

  defp candidate_mode(value) when is_binary(value) and value != "", do: "fixed"
  defp candidate_mode(_value), do: "context"

  defp candidate_fingerprint(params) do
    params
    |> Map.take([
      "candidate_point_id",
      "candidate_title",
      "candidate_widget_type",
      "candidate_spacecraft_id",
      "candidate_realm",
      "candidate_data_view",
      "candidate_data_source_id",
      "candidate_source_binding_id",
      "candidate_library_item_id",
      "candidate_library_version"
    ])
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp build_library_placement(item_id, version, widget_definition) do
    widget_def = WidgetDef.from_map(widget_definition)

    %Placement{
      placement_id: Cadence.Ids.new("placement"),
      layout: library_layout(widget_def.widget_type_id),
      content_kind: :library,
      widget_def: widget_def,
      library_widget_id: item_id,
      library_version: version
    }
  end

  defp library_layout("value_tile"), do: %{x: 0, y: 0, w: 3, h: 3}
  defp library_layout(_widget_type), do: %{x: 0, y: 0, w: 6, h: 6}

  defp default_title(point_id) do
    point_id
    |> String.replace(["_", "."], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil

  defp dashboard_path(socket) do
    "/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards/#{socket.assigns.dashboard_document.dashboard_id}"
  end
end
