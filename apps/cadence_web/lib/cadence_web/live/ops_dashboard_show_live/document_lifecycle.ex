defmodule CadenceWeb.OpsDashboardShowLive.DocumentLifecycle do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Cadence.Dashboards.{
    DashboardLifecycleStatus,
    DataSources,
    Document,
    PublishReadinessPayload,
    RenderItem,
    SourceHealth
  }

  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  def fetch_operator_document(scope, mission, dashboard_id) do
    case Cadence.Dashboards.fetch_document_for_mode(
           scope.organization_id,
           mission.mission_id,
           dashboard_id,
           :view
         ) do
      {:ok, document} ->
        {:ok, document, :published}

      {:error, :dashboard_not_published} ->
        case Cadence.Dashboards.fetch_document_for_mode(
               scope.organization_id,
               mission.mission_id,
               dashboard_id,
               :edit
             ) do
          {:ok, document} -> {:ok, document, :draft_preview}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def assign_document(socket, %Document{} = document, document_mode) do
    socket
    |> assign(:dashboard_document, document)
    |> assign(:dashboard_document_mode, document_mode)
    |> assign_render_items()
    |> assign(:page_title, document.name)
  end

  def assign_render_items(socket) do
    document = socket.assigns[:dashboard_document]
    scope_context = socket.assigns[:dashboard_scope_context]

    case document do
      %Document{} = document ->
        assign(socket, :dashboard_render_items, RenderItem.from_document(document, scope_context))

      _missing ->
        assign(socket, :dashboard_render_items, [])
    end
  end

  def assign_versions(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    summaries =
      Cadence.Dashboards.list_dashboard_summaries(scope.organization_id, mission.mission_id)

    summary = Enum.find(summaries, &(&1.dashboard_id == document.dashboard_id))

    lifecycle_events =
      Cadence.Dashboards.list_lifecycle_events(
        scope.organization_id,
        mission.mission_id,
        document.dashboard_id
      )

    comparison_review_queue =
      Cadence.Dashboards.dashboard_comparison_review_queue(
        scope.organization_id,
        mission.mission_id,
        document.dashboard_id
      )

    socket
    |> assign(
      :dashboard_versions,
      Cadence.Dashboards.list_versions(
        scope.organization_id,
        mission.mission_id,
        document.dashboard_id
      )
    )
    |> assign(:dashboard_summary, summary)
    |> assign(:dashboard_lifecycle_status, Cadence.Dashboards.dashboard_lifecycle_status(summary))
    |> assign(:dashboard_lifecycle_events, lifecycle_events)
    |> assign(:dashboard_comparison_review_queue, comparison_review_queue)
    |> assign(
      :dashboard_source_action_events,
      list_source_action_events(scope.organization_id, mission.mission_id)
    )
    |> assign(:ops_dashboards, summaries)
  end

  defp list_source_action_events(organization_id, mission_id) do
    data_bindings = DataSources.list_data_bindings(organization_id, mission_id)

    health_events =
      SourceHealth.list_source_health_events(organization_id, mission_id, limit: 50)

    source_events =
      DataSources.list_data_source_events(organization_id, mission_id, limit: 50)

    binding_events =
      data_bindings
      |> Enum.flat_map(&DataSources.list_data_binding_events(&1.binding_id, limit: 10))
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})
      |> Enum.take(50)

    (health_events ++ source_events ++ binding_events)
    |> Enum.sort_by(&source_action_event_time/1, {:desc, DateTime})
    |> Enum.take(100)
  end

  defp source_action_event_time(%{observed_at: %DateTime{} = observed_at}), do: observed_at
  defp source_action_event_time(%{occurred_at: %DateTime{} = occurred_at}), do: occurred_at

  def assign_publish_validation(socket) do
    case fetch_edit_document(socket) do
      {:ok, %Document{} = draft_document} ->
        assign_publish_validation_result(
          socket,
          validate_publish_readiness(socket, draft_document),
          draft_document
        )

      {:error, _reason} ->
        socket
        |> assign(:dashboard_publish_validation, nil)
        |> assign(:dashboard_publish_validation_freshness, nil)
    end
  end

  def refresh_publish_validation(socket, opts \\ []) do
    case fetch_edit_document(socket) do
      {:ok, %Document{} = draft_document} ->
        validation = validate_publish_readiness(socket, draft_document)

        socket
        |> assign_publish_validation_result(validation, draft_document)
        |> record_publish_readiness_check(draft_document, validation, opts)

      {:error, _reason} ->
        socket
        |> assign(:dashboard_publish_validation, nil)
        |> assign(:dashboard_publish_validation_freshness, nil)
    end
  end

  defdelegate publish_validation_freshness_for(document, summary, validation \\ nil),
    to: PublishReadinessPayload

  defdelegate publish_readiness_payload_for(document, validation, summary \\ nil),
    to: PublishReadinessPayload

  def archive_document(socket, opts) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case Cadence.Dashboards.archive_document(
           scope.organization_id,
           mission.mission_id,
           document.dashboard_id,
           expected_version: latest_known_version(socket),
           actor_id: current_user_id(scope)
         ) do
      :ok ->
        socket
        |> put_flash(:info, "Dashboard archived.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, :dashboard_not_found} ->
        put_flash(socket, :error, "Dashboard not found.")

      {:error, {:dashboard_version_conflict, current_version}} ->
        reload_conflicted_document(socket, current_version, opts)

      {:error, reason} ->
        put_flash(socket, :error, "Failed to archive dashboard: #{inspect(reason)}")
    end
  end

  def publish_latest_draft(socket, opts) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    expected_version = latest_known_version(socket)

    with :ok <- validate_publish_shortcut_available(socket.assigns.dashboard_lifecycle_status),
         {:ok, %Document{} = draft_document} <-
           fetch_edit_document(socket),
         validation <- validate_publish_readiness(socket, draft_document),
         :ok <- validate_publishable(validation),
         {:ok, published_version} <-
           Cadence.Dashboards.publish_document(
             scope.organization_id,
             mission.mission_id,
             document.dashboard_id,
             Document.version(draft_document),
             expected_version: expected_version,
             published_by: current_user_id(scope)
           ) do
      socket
      |> assign(:edit_mode?, false)
      |> assign(:panel, nil)
      |> assign(:dashboard_publish_validation, validation)
      |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
      |> assign_document(published_version.document, :published)
      |> assign_versions()
      |> assign_publish_validation()
      |> put_flash(:info, "Dashboard published.")
      |> Runtime.resolve_engine(:context_change, reason: :dashboard_published)
    else
      {:error, :dashboard_not_found} ->
        socket
        |> put_flash(:error, "Dashboard not found.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, {:dashboard_version_conflict, current_version}} ->
        reload_conflicted_document(socket, current_version, opts)

      {:error, {:dashboard_publish_validation_failed, validation}} ->
        socket
        |> assign(:panel, :versions)
        |> assign_publish_validation_result(validation)
        |> put_flash(:error, "Dashboard has validation errors. Fix them before publishing.")

      {:error, :dashboard_publish_not_available} ->
        put_flash(socket, :info, "No draft changes to publish.")

      {:error, reason} ->
        put_flash(socket, :error, "Failed to publish dashboard: #{inspect(reason)}")
    end
  end

  def publish_version(socket, version_param, opts) do
    with {version, ""} <- Integer.parse(version_param),
         true <- version > 0 do
      do_publish_version(socket, version, opts)
    else
      _invalid ->
        put_flash(socket, :error, "Invalid dashboard version.")
    end
  end

  def restore_version_as_draft(socket, version_param, opts) do
    with {version, ""} <- Integer.parse(version_param),
         true <- version > 0 do
      do_restore_version_as_draft(socket, version, opts)
    else
      _invalid ->
        put_flash(socket, :error, "Invalid dashboard version.")
    end
  end

  def persist_document_socket(socket, %Document{} = document, opts, nav_opts, on_success \\ & &1) do
    case persist_document(socket, document, opts, nav_opts) do
      {:ok, socket} -> on_success.(socket)
      {:error, socket} -> socket
    end
  end

  def persist_document(socket, %Document{} = document, opts, nav_opts) do
    %{
      current_scope: scope,
      current_mission: mission,
      dashboard_document: current_document
    } = socket.assigns

    case Cadence.Dashboards.update_document(
           scope.organization_id,
           mission.mission_id,
           current_document.dashboard_id,
           document,
           Keyword.merge(opts,
             expected_version: Document.version(current_document),
             created_by: current_user_id(scope)
           )
         ) do
      {:ok, updated_document} ->
        {:ok,
         socket
         |> assign_document(updated_document, :draft)
         |> assign_versions()
         |> assign_publish_validation()}

      {:error, {:dashboard_version_conflict, current_version}} ->
        {:error, reload_conflicted_document(socket, current_version, nav_opts)}

      {:error, reason} ->
        {:error, put_flash(socket, :error, "Failed to save dashboard: #{inspect(reason)}")}
    end
  end

  def save_runtime_defaults(socket, nav_opts) do
    case runtime_defaults_base_document(socket) do
      {:ok, %Document{} = base_document} ->
        document = put_runtime_defaults(base_document, socket)
        persist_runtime_defaults_document(socket, document, nav_opts)

      {:error, :dashboard_not_found} ->
        {:error, put_flash(socket, :error, "Dashboard not found.")}

      {:error, :dashboard_archived} ->
        {:error, put_flash(socket, :error, "Dashboard is archived.")}

      {:error, reason} ->
        {:error,
         put_flash(socket, :error, "Failed to save dashboard defaults: #{inspect(reason)}")}
    end
  end

  def publication_state(%DashboardLifecycleStatus{publication_state: state}),
    do: Atom.to_string(state)

  def publication_state(_status), do: "unknown"

  def publishable_version(%DashboardLifecycleStatus{publishable_version: version})
      when is_integer(version),
      do: Integer.to_string(version)

  def publishable_version(_status), do: nil

  def lifecycle_flag(%DashboardLifecycleStatus{} = status, field) do
    if Map.get(status, field), do: "true", else: "false"
  end

  def lifecycle_flag(_status, _field), do: "false"

  def draft_runtime_defaults_differ?(
        %{published_version: published, draft_version: draft},
        versions
      )
      when is_integer(published) and is_integer(draft) and published != draft and
             is_list(versions) do
    with %{document: %Document{} = published_document} <- version_by_number(versions, published),
         %{document: %Document{} = draft_document} <- version_by_number(versions, draft) do
      runtime_defaults(published_document) != runtime_defaults(draft_document)
    else
      _missing_version -> false
    end
  end

  def draft_runtime_defaults_differ?(_summary, _versions), do: false

  def version_publish_unavailable_message(:already_published),
    do: "Dashboard version is already published."

  def version_publish_unavailable_message(:archived),
    do: "Archived dashboards cannot publish versions."

  def version_publish_unavailable_message(_reason),
    do: "Dashboard version cannot be published."

  def version_restore_unavailable_message(:already_latest),
    do: "Dashboard version is already the latest draft."

  def version_restore_unavailable_message(:archived),
    do: "Archived dashboards cannot restore versions."

  def version_restore_unavailable_message(_reason),
    do: "Dashboard version cannot be restored."

  def latest_known_version(socket) do
    socket.assigns.dashboard_versions
    |> Enum.map(& &1.version)
    |> Enum.max(fn -> Document.version(socket.assigns.dashboard_document) end)
  end

  def reload_conflicted_document(socket, current_version, opts) do
    %{
      current_scope: scope,
      current_mission: mission,
      dashboard_document: current_document
    } = socket.assigns

    case Cadence.Dashboards.fetch_document(
           scope.organization_id,
           mission.mission_id,
           current_document.dashboard_id
         ) do
      {:ok, latest_document} ->
        latest_version = current_version || Document.version(latest_document)

        socket
        |> assign_document(latest_document, :draft)
        |> assign_versions()
        |> put_flash(
          :error,
          "Dashboard changed in another session. Reloaded version #{latest_version}; review your change and try again."
        )

      {:error, :dashboard_not_found} ->
        socket
        |> put_flash(:error, "Dashboard changed in another session and is no longer available.")
        |> push_navigate(to: dashboard_list_path(opts, socket))
    end
  end

  def current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  def current_user_id(_scope), do: nil

  defp do_publish_version(socket, version, opts) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    with :ok <- validate_version_publish_available(socket, version),
         {:ok, published_version} <-
           Cadence.Dashboards.publish_document(
             scope.organization_id,
             mission.mission_id,
             document.dashboard_id,
             version,
             expected_version: latest_known_version(socket),
             published_by: current_user_id(scope)
           ) do
      socket
      |> assign(:edit_mode?, false)
      |> assign(:panel, nil)
      |> assign(
        :dashboard_publish_validation,
        validate_publish_readiness(socket, published_version.document)
      )
      |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
      |> assign_document(published_version.document, :published)
      |> assign_versions()
      |> assign_publish_validation()
      |> put_flash(:info, "Dashboard version #{version} published.")
      |> Runtime.resolve_engine(:context_change, reason: :dashboard_published)
    else
      {:error, {:dashboard_version_publish_not_available, reason}} ->
        put_flash(socket, :info, version_publish_unavailable_message(reason))

      {:error, :dashboard_not_found} ->
        socket
        |> put_flash(:error, "Dashboard not found.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, :dashboard_version_not_found} ->
        put_flash(socket, :error, "Dashboard version not found.")

      {:error, {:dashboard_version_conflict, current_version}} ->
        reload_conflicted_document(socket, current_version, opts)

      {:error, {:invalid_dashboard_document, validation}} ->
        socket
        |> assign(:panel, :versions)
        |> assign_publish_validation_result(validation)
        |> put_flash(
          :error,
          "Dashboard version has validation errors. Fix them before publishing."
        )

      {:error, reason} ->
        put_flash(socket, :error, "Failed to publish dashboard version: #{inspect(reason)}")
    end
  end

  defp do_restore_version_as_draft(socket, version, opts) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    with :ok <- validate_version_restore_available(socket, version),
         {:ok, reverted_version} <-
           Cadence.Dashboards.revert_document(
             scope.organization_id,
             mission.mission_id,
             document.dashboard_id,
             version,
             expected_version: latest_known_version(socket),
             created_by: current_user_id(scope)
           ) do
      socket
      |> assign(:edit_mode?, true)
      |> assign(:panel, nil)
      |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
      |> assign_document(reverted_version.document, :draft)
      |> assign_versions()
      |> assign_publish_validation()
      |> put_flash(:info, "Restored version #{version} as draft.")
    else
      {:error, {:dashboard_version_restore_not_available, reason}} ->
        put_flash(socket, :info, version_restore_unavailable_message(reason))

      {:error, :dashboard_not_found} ->
        socket
        |> put_flash(:error, "Dashboard not found.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, :dashboard_version_not_found} ->
        put_flash(socket, :error, "Dashboard version not found.")

      {:error, {:dashboard_version_conflict, current_version}} ->
        reload_conflicted_document(socket, current_version, opts)

      {:error, reason} ->
        put_flash(socket, :error, "Failed to restore dashboard version: #{inspect(reason)}")
    end
  end

  defp runtime_defaults_base_document(%{assigns: %{dashboard_document_mode: :published}} = socket) do
    fetch_edit_document(socket)
  end

  defp runtime_defaults_base_document(%{assigns: %{dashboard_document: %Document{} = document}}),
    do: {:ok, document}

  defp persist_runtime_defaults_document(socket, %Document{} = document, nav_opts) do
    previous_document_mode = socket.assigns.dashboard_document_mode

    case persist_document(
           socket,
           document,
           [change_summary: "Updated runtime defaults"],
           nav_opts
         ) do
      {:ok, socket} ->
        {:ok, restore_operator_document_after_runtime_defaults(socket, previous_document_mode)}

      {:error, socket} ->
        {:error, socket}
    end
  end

  defp restore_operator_document_after_runtime_defaults(socket, :draft),
    do: socket

  defp restore_operator_document_after_runtime_defaults(socket, :draft_preview),
    do: socket

  defp restore_operator_document_after_runtime_defaults(socket, _previous_document_mode) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case fetch_operator_document(scope, mission, document.dashboard_id) do
      {:ok, operator_document, document_mode} ->
        socket
        |> assign_document(operator_document, document_mode)
        |> assign_versions()

      {:error, _reason} ->
        socket
    end
  end

  defp put_runtime_defaults(%Document{} = document, socket) do
    defaults =
      document.defaults
      |> ensure_map()
      |> Map.put("data", runtime_default_data_context(socket))

    %Document{document | defaults: defaults}
  end

  defp runtime_default_data_context(socket) do
    socket.assigns.dashboard_data_context
    |> RuntimeQuery.runtime_default_data_context()
  end

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp version_by_number(versions, version) do
    Enum.find(versions, &(&1.version == version))
  end

  defp runtime_defaults(%Document{} = document) do
    RuntimeQuery.document_data_defaults(document)
  end

  defp fetch_edit_document(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    Cadence.Dashboards.fetch_document_for_mode(
      scope.organization_id,
      mission.mission_id,
      document.dashboard_id,
      :edit
    )
  end

  defp validate_publish_shortcut_available(%DashboardLifecycleStatus{publish_available?: true}),
    do: :ok

  defp validate_publish_shortcut_available(_status),
    do: {:error, :dashboard_publish_not_available}

  defp validate_version_publish_available(socket, version) do
    case Cadence.Dashboards.dashboard_version_action(socket.assigns.dashboard_summary, version) do
      %{publish_available?: true} -> :ok
      %{publish_reason: reason} -> {:error, {:dashboard_version_publish_not_available, reason}}
    end
  end

  defp validate_version_restore_available(socket, version) do
    case Cadence.Dashboards.dashboard_version_action(socket.assigns.dashboard_summary, version) do
      %{restore_available?: true} -> :ok
      %{restore_reason: reason} -> {:error, {:dashboard_version_restore_not_available, reason}}
    end
  end

  defp validate_publishable(%{valid?: true}), do: :ok

  defp validate_publishable(validation) do
    {:error, {:dashboard_publish_validation_failed, validation}}
  end

  defp assign_publish_validation_result(socket, validation, document \\ nil) do
    document = document || Map.get(socket.assigns, :dashboard_document)

    socket
    |> assign(:dashboard_publish_validation, validation)
    |> assign(
      :dashboard_publish_validation_freshness,
      publish_validation_freshness(socket, document)
    )
  end

  defp publish_validation_freshness(socket, %Document{} = document) do
    summary = Map.get(socket.assigns, :dashboard_summary)
    validation = Map.get(socket.assigns, :dashboard_publish_validation)

    publish_validation_freshness_for(document, summary, validation)
  end

  defp publish_validation_freshness(_socket, _document), do: nil

  defp validate_publish_readiness(socket, %Document{} = document) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    Cadence.Dashboards.validate_publish_readiness(
      scope.organization_id,
      mission.mission_id,
      document
    )
  end

  defp record_publish_readiness_check(socket, %Document{} = document, validation, opts) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.Dashboards.record_dashboard_publish_readiness_check(
           scope.organization_id,
           mission.mission_id,
           document.dashboard_id,
           document,
           validation,
           Map.get(socket.assigns, :dashboard_summary),
           actor_id: current_user_id(scope),
           occurred_at: Keyword.get(opts, :occurred_at, DateTime.utc_now())
         ) do
      {:ok, _event} ->
        assign_versions(socket)

      {:error, reason} ->
        put_flash(
          socket,
          :error,
          "Publish readiness was checked, but the audit event was not recorded: #{inspect(reason)}"
        )
    end
  end

  defp dashboard_list_path(opts, socket) do
    opts
    |> Keyword.fetch!(:dashboard_list_path)
    |> then(& &1.(socket))
  end
end
