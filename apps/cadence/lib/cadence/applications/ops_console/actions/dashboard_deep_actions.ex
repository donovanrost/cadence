defmodule Cadence.Applications.OpsConsole.Actions.DashboardDeepActions do
  @moduledoc """
  Exact action adapter for the federated dashboard editor and activity surfaces.

  Dashboard viewer actions are intentionally absent.  The editor and activity
  routes are already protected by the dashboard author policy; this adapter
  repeats that policy at the action boundary so a forged host request cannot
  turn the viewer surface into an authoring surface.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, PlacementEditor, Section}

  @application_key "ops_console"
  @application_version 1
  @surface_version 1

  @editor_actions [
    "layout_changed",
    "validate_dashboard_section",
    "save_dashboard_section",
    "remove_dashboard_section",
    "move_dashboard_section",
    "preview_widget_binding",
    "validate_widget",
    "save_widget",
    "remove_widget",
    "rename",
    "archive_dashboard",
    "publish_dashboard",
    "publish_dashboard_version",
    "save_runtime_defaults",
    "restore_version_as_draft",
    "save_editor",
    "review_editor",
    "discard_editor",
    "reload_editor"
  ]

  @activity_actions ["publish_version", "restore_version"]

  @bindings Enum.map(@editor_actions, &{"dashboard_editor", &1}) ++
              Enum.map(@activity_actions, &{"dashboard_activity", &1})

  @section_keys ["section_id", "title", "description", "collapsed_by_default"]
  @widget_keys ~w(
    type title mode spacecraft_id scope_kind scope_id section_id binding_source
    precision window_seconds show_unit show_min_max_band legend_mode line_width
    fill_opacity span_gaps show_points axis_mode shared_tooltip repeat_over
    repeat_layout repeat_max_instances point_q widget_id
  )

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @bindings

  @spec execute(Scope.t(), HostContext.t(), ActionRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    execute(scope, host_context, request.surface_id, request)
  end

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id} = host_context,
        surface_id,
        %ActionRequest{
          application_key: @application_key,
          application_version: @application_version,
          surface_id: surface_id,
          surface_version: @surface_version,
          action_id: action_id,
          params: params
        }
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" and is_binary(surface_id) and is_binary(action_id) and
             is_map(params) do
    with :ok <- validate_host_context(host_context),
         :ok <- validate_binding(surface_id, action_id),
         :ok <- JSONBoundary.validate(params),
         {:ok, dashboard_id} <- validate_params(surface_id, action_id, params),
         :ok <- authorize(scope, organization_id, mission_id),
         {:ok, result} <-
           dispatch(scope, organization_id, mission_id, dashboard_id, action_id, params) do
      safe_result(result)
    end
  end

  def execute(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term() | nil
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  defp validate_host_context(%HostContext{} = context) do
    if HostContext.valid?(context), do: :ok, else: {:error, :invalid_host_context}
  end

  defp validate_binding(surface_id, action_id) do
    if {surface_id, action_id} in @bindings,
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp validate_params(surface_id, action_id, params) do
    with :ok <- exact_keys(params, ["dashboard_id"] ++ action_keys(surface_id, action_id)),
         :ok <- required_text(params, "dashboard_id"),
         :ok <- validate_action_params(action_id, params) do
      {:ok, params["dashboard_id"]}
    end
  end

  defp action_keys("dashboard_activity", _action_id), do: ["version"]
  defp action_keys("dashboard_editor", "layout_changed"), do: ["layouts"]

  defp action_keys("dashboard_editor", action_id)
       when action_id in ["validate_dashboard_section", "save_dashboard_section"],
       do: ["section"]

  defp action_keys("dashboard_editor", "move_dashboard_section"), do: ["section-id", "direction"]
  defp action_keys("dashboard_editor", "remove_dashboard_section"), do: ["section-id"]

  defp action_keys("dashboard_editor", action_id)
       when action_id in ["validate_widget", "save_widget"],
       do: ["widget"]

  defp action_keys("dashboard_editor", "remove_widget"), do: ["widget-id"]
  defp action_keys("dashboard_editor", "rename"), do: ["dashboard"]
  defp action_keys("dashboard_editor", "publish_dashboard_version"), do: ["version"]
  defp action_keys("dashboard_editor", "restore_version_as_draft"), do: ["version"]
  defp action_keys("dashboard_editor", _action_id), do: []

  defp validate_action_params("layout_changed", %{"layouts" => layouts})
       when is_list(layouts) do
    if Enum.all?(layouts, &valid_layout?/1), do: :ok, else: {:error, :invalid_action_input}
  end

  defp validate_action_params(action_id, %{"section" => section})
       when action_id in ["validate_dashboard_section", "save_dashboard_section"] do
    with :ok <- exact_keys(section, @section_keys),
         :ok <- required_text(section, "section_id"),
         :ok <- required_text(section, "title"),
         true <- is_binary(section["description"]),
         true <- is_boolean(section["collapsed_by_default"]) do
      :ok
    else
      false -> {:error, :invalid_action_input}
      error -> error
    end
  end

  defp validate_action_params(action_id, params)
       when action_id in ["remove_dashboard_section", "move_dashboard_section"] do
    with :ok <- required_text(params, "section-id") do
      optional_direction(action_id, params)
    end
  end

  defp validate_action_params(action_id, %{"widget" => widget})
       when action_id in ["validate_widget", "save_widget"] do
    if is_map(widget) and Enum.all?(Map.keys(widget), &(&1 in @widget_keys)),
      do: :ok,
      else: {:error, :invalid_action_input}
  end

  defp validate_action_params("remove_widget", params), do: required_text(params, "widget-id")

  defp validate_action_params("rename", %{"dashboard" => dashboard}) do
    with :ok <- exact_keys(dashboard, ["name", "description"]),
         :ok <- required_text(dashboard, "name"),
         true <- is_binary(dashboard["description"]) do
      :ok
    else
      false -> {:error, :invalid_action_input}
      error -> error
    end
  end

  defp validate_action_params(action_id, params)
       when action_id in [
              "publish_dashboard_version",
              "restore_version_as_draft",
              "publish_version",
              "restore_version"
            ],
       do: positive_version(params["version"])

  defp validate_action_params(_action_id, _params), do: :ok

  defp valid_layout?(layout) when is_map(layout) do
    keys = Map.keys(layout)

    Enum.all?(keys, &is_binary/1) and
      Enum.sort(keys) == Enum.sort(["widget_id", "x", "y", "w", "h"]) and
      is_binary(layout["widget_id"]) and
      Enum.all?(~w(x y w h), &(is_integer(layout[&1]) and layout[&1] >= 0))
  end

  defp valid_layout?(_layout), do: false

  defp optional_direction("move_dashboard_section", %{"direction" => direction})
       when direction in ["up", "down"],
       do: :ok

  defp optional_direction("move_dashboard_section", _params),
    do: {:error, :invalid_action_input}

  defp optional_direction(_action_id, _params), do: :ok

  defp authorize(scope, organization_id, mission_id) do
    Policy.authorize(scope, :author_dashboards, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  defp dispatch(scope, organization_id, mission_id, dashboard_id, action_id, params) do
    dispatch_action(
      action_id,
      scope,
      organization_id,
      mission_id,
      dashboard_id,
      params
    )
  end

  defp dispatch_action(
         "layout_changed",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do:
         mutate(
           scope,
           mission_id,
           dashboard_id,
           &Document.apply_layouts(&1, params["layouts"]),
           "Layout updated"
         )

  defp dispatch_action(
         "validate_dashboard_section",
         _scope,
         organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: validate_section(organization_id, mission_id, dashboard_id, params["section"])

  defp dispatch_action(
         "save_dashboard_section",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do:
         mutate(
           scope,
           mission_id,
           dashboard_id,
           &Document.put_section(&1, Section.from_map(params["section"])),
           "Section saved"
         )

  defp dispatch_action(
         "remove_dashboard_section",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do:
         mutate(
           scope,
           mission_id,
           dashboard_id,
           &Document.remove_section(&1, params["section-id"]),
           "Section removed"
         )

  defp dispatch_action(
         "move_dashboard_section",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: move_section(scope, mission_id, dashboard_id, params)

  defp dispatch_action(
         "preview_widget_binding",
         _scope,
         organization_id,
         mission_id,
         dashboard_id,
         _params
       ),
       do: current_document(organization_id, mission_id, dashboard_id, "Widget binding preview")

  defp dispatch_action(
         "validate_widget",
         _scope,
         organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: validate_widget(organization_id, mission_id, dashboard_id, params["widget"])

  defp dispatch_action("save_widget", scope, _organization_id, mission_id, dashboard_id, params),
    do: save_widget(scope, mission_id, dashboard_id, params["widget"])

  defp dispatch_action(
         "remove_widget",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do:
         mutate(
           scope,
           mission_id,
           dashboard_id,
           &Document.remove_placement(&1, params["widget-id"]),
           "Widget removed"
         )

  defp dispatch_action("rename", scope, _organization_id, mission_id, dashboard_id, params),
    do:
      mutate(
        scope,
        mission_id,
        dashboard_id,
        &rename_document(&1, params["dashboard"]),
        "Dashboard renamed"
      )

  defp dispatch_action(
         "archive_dashboard",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         _params
       ),
       do: archive_dashboard(scope, mission_id, dashboard_id)

  defp dispatch_action(
         "publish_dashboard",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         _params
       ),
       do: publish(scope, mission_id, dashboard_id, nil)

  defp dispatch_action(
         "publish_dashboard_version",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: publish(scope, mission_id, dashboard_id, params["version"])

  defp dispatch_action(
         "save_runtime_defaults",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         _params
       ),
       do: mutate(scope, mission_id, dashboard_id, & &1, "Runtime defaults saved")

  defp dispatch_action(
         "restore_version_as_draft",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: restore(scope, mission_id, dashboard_id, params["version"])

  defp dispatch_action(action_id, scope, _organization_id, mission_id, dashboard_id, _params)
       when action_id in ["save_editor", "review_editor"],
       do: mutate(scope, mission_id, dashboard_id, & &1, "Editor saved")

  defp dispatch_action(action_id, _scope, organization_id, mission_id, dashboard_id, _params)
       when action_id in ["discard_editor", "reload_editor"],
       do: current_document(organization_id, mission_id, dashboard_id, "Editor reloaded")

  defp dispatch_action(
         "publish_version",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: publish(scope, mission_id, dashboard_id, params["version"])

  defp dispatch_action(
         "restore_version",
         scope,
         _organization_id,
         mission_id,
         dashboard_id,
         params
       ),
       do: restore(scope, mission_id, dashboard_id, params["version"])

  defp current_document(organization_id, mission_id, dashboard_id, status) do
    with {:ok, %Document{} = document} <-
           Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit) do
      {:ok, receipt(status, document)}
    end
  end

  defp mutate(scope, mission_id, dashboard_id, transform, summary) do
    with {:ok, %Document{} = document} <- fetch(scope.organization_id, mission_id, dashboard_id),
         next <- transform.(document),
         {:ok, %Document{} = persisted} <-
           Dashboards.update_document(scope.organization_id, mission_id, dashboard_id, next,
             expected_version: Document.version(document),
             created_by: actor_id(scope),
             change_summary: summary
           ) do
      {:ok, receipt(summary, persisted)}
    end
  end

  defp validate_section(organization_id, mission_id, dashboard_id, section) do
    with {:ok, document} <-
           Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit),
         next <- Document.put_section(document, Section.from_map(section)),
         validation <- Dashboards.validate_document(next) do
      {:ok,
       %{"status" => "validated", "dashboardId" => dashboard_id, "valid" => validation.valid?}}
    end
  end

  defp validate_widget(organization_id, mission_id, dashboard_id, widget) do
    with {:ok, document} <-
           Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit),
         {:ok, _placement} <- build_placement(widget, document, nil) do
      {:ok, %{"status" => "validated", "dashboardId" => dashboard_id, "valid" => true}}
    end
  end

  defp save_widget(scope, mission_id, dashboard_id, widget) do
    with {:ok, document} <- fetch(scope.organization_id, mission_id, dashboard_id),
         placement_id <- widget["widget_id"],
         existing <- Enum.find(document.placements, &(&1.placement_id == placement_id)),
         {:ok, placement} <- build_placement(widget, document, existing),
         next <- Document.put_placement(document, placement),
         {:ok, persisted} <-
           Dashboards.update_document(scope.organization_id, mission_id, dashboard_id, next,
             expected_version: Document.version(document),
             created_by: actor_id(scope),
             change_summary: "Widget saved"
           ) do
      {:ok, receipt("Widget saved", persisted)}
    end
  end

  defp build_placement(widget, document, existing) do
    selected = widget["point_q"] || ""
    panel = if existing, do: {:edit_placement, existing.placement_id}, else: :add_widget

    PlacementEditor.build_placement(widget, selected, panel, existing,
      organization_id: document.organization_id,
      mission_id: document.mission_id
    )
  end

  defp move_section(scope, mission_id, dashboard_id, params) do
    direction = if params["direction"] == "up", do: :up, else: :down

    mutate(
      scope,
      mission_id,
      dashboard_id,
      &Document.move_section(&1, params["section-id"], direction),
      "Section moved"
    )
  end

  defp rename_document(%Document{} = document, dashboard) do
    %Document{document | name: dashboard["name"], description: dashboard["description"]}
  end

  defp archive_dashboard(scope, mission_id, dashboard_id) do
    with :ok <-
           Dashboards.archive_document(scope.organization_id, mission_id, dashboard_id,
             actor_id: actor_id(scope)
           ) do
      {:ok, %{"status" => "archived", "dashboardId" => dashboard_id}}
    end
  end

  defp publish(scope, mission_id, dashboard_id, version) do
    with {:ok, document} <- fetch(scope.organization_id, mission_id, dashboard_id),
         {:ok, version} <- version_number(version || Document.version(document)),
         {:ok, published} <-
           Dashboards.publish_document(scope.organization_id, mission_id, dashboard_id, version,
             expected_version: Document.version(document),
             published_by: actor_id(scope)
           ) do
      {:ok,
       %{"status" => "published", "dashboardId" => dashboard_id, "version" => published.version}}
    end
  end

  defp restore(scope, mission_id, dashboard_id, version) do
    with {:ok, document} <- fetch(scope.organization_id, mission_id, dashboard_id),
         {:ok, version} <- version_number(version),
         {:ok, restored} <-
           Dashboards.revert_document(scope.organization_id, mission_id, dashboard_id, version,
             expected_version: Document.version(document),
             created_by: actor_id(scope)
           ) do
      {:ok,
       %{"status" => "restored", "dashboardId" => dashboard_id, "version" => restored.version}}
    end
  end

  defp fetch(organization_id, mission_id, dashboard_id),
    do: Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit)

  defp receipt(status, %Document{} = document) do
    %{
      "status" => status,
      "dashboardId" => document.dashboard_id,
      "version" => Document.version(document)
    }
  end

  defp safe_result({:ok, result}) do
    case JSONBoundary.safe(result) do
      {:ok, safe} -> {:ok, safe}
      {:error, reason} -> {:error, {:unsafe_action_receipt, reason}}
    end
  end

  defp safe_result(error), do: error

  defp exact_keys(map, expected) when is_map(map) do
    keys = Map.keys(map)

    if Enum.all?(keys, &is_binary/1) and Enum.sort(keys) == Enum.sort(expected),
      do: :ok,
      else: {:error, :invalid_action_input}
  end

  defp exact_keys(_map, _expected), do: {:error, :invalid_action_input}

  defp required_text(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) and byte_size(value) > 0 -> :ok
      _value -> {:error, {:missing_field, key}}
    end
  end

  defp required_text(_map, _key), do: {:error, :invalid_action_input}

  defp positive_version(value) when is_binary(value) do
    case Integer.parse(value) do
      {version, ""} when version > 0 -> :ok
      _invalid -> {:error, :invalid_action_input}
    end
  end

  defp positive_version(_value), do: {:error, :invalid_action_input}

  defp version_number(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp version_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {version, ""} when version > 0 -> {:ok, version}
      _invalid -> {:error, :invalid_action_input}
    end
  end

  defp version_number(_value), do: {:error, :invalid_action_input}

  defp actor_id(%Scope{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp actor_id(_scope), do: nil
end
