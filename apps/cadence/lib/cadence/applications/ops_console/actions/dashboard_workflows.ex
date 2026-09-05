defmodule Cadence.Applications.OpsConsole.Actions.DashboardWorkflows do
  @moduledoc """
  First-party host action adapter for the dashboard route surfaces.

  The surface identity is deliberately supplied separately from the request
  until the shared host request type carries it. Every durable operation below
  remains delegated to the existing dashboard context.
  """

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards
  alias Cadence.Dashboards.{DashboardPlaylist, Document, Management}

  @application_key "ops_console"
  @application_version 1

  @bindings [
    {"dashboard_directory", "filter_dashboards"},
    {"dashboard_directory", "toggle_dashboard_star"},
    {"dashboard_directory", "restore_dashboard"},
    {"dashboard_new", "validate"},
    {"dashboard_new", "save"},
    {"dashboard_library", "stage-library-item"},
    {"dashboard_library", "create-library-item"},
    {"dashboard_library", "add-library-version"},
    {"dashboard_playlists", "create-playlist"},
    {"dashboard_playlist_present", "next-dashboard"},
    {"dashboard_settings", "validate-settings"},
    {"dashboard_settings", "save-settings"},
    {"dashboard_settings", "create-share"},
    {"dashboard_settings", "revoke-share"},
    {"dashboard_settings", "create-snapshot"},
    {"dashboard_settings", "archive-dashboard"}
  ]

  @filter_keys ~w(query lifecycle tag sort)
  @new_dashboard_keys ~w(name description document_json)
  @library_item_optional_keys ~w(description change_summary)
  @settings_keys ~w(name description tags defaults_json)

  @spec bindings() :: [{binary(), binary()}]
  def bindings, do: @bindings

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id} = host_context,
        surface_id,
        %ActionRequest{
          application_key: @application_key,
          application_version: @application_version,
          action_id: action_id,
          params: params
        }
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" and is_binary(surface_id) and is_binary(action_id) and
             is_map(params) do
    with :ok <- validate_binding(surface_id, action_id),
         :ok <- validate_host_context(host_context),
         :ok <- validate_params(params),
         :ok <- validate_mission_param(mission_id, params),
         :ok <- authorize(scope, organization_id, mission_id),
         {:ok, result} <-
           dispatch(
             scope,
             host_context,
             organization_id,
             mission_id,
             surface_id,
             action_id,
             params
           ) do
      {:ok, result}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :unsupported_application_action}
    end
  end

  def execute(%Scope{}, %HostContext{}, _surface_id, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term()
  def result(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  defp dispatch(
         _scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_directory",
         "filter_dashboards",
         params
       ),
       do: filter_dashboards(organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_directory",
         "toggle_dashboard_star",
         params
       ),
       do: toggle_dashboard_star(scope, organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_directory",
         "restore_dashboard",
         params
       ),
       do: restore_dashboard(scope, organization_id, mission_id, params)

  defp dispatch(
         _scope,
         _host_context,
         _organization_id,
         _mission_id,
         "dashboard_new",
         "validate",
         params
       ),
       do: validate_dashboard(params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_new",
         "save",
         params
       ),
       do: save_dashboard(scope, organization_id, mission_id, params)

  defp dispatch(
         _scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_library",
         "stage-library-item",
         params
       ),
       do: stage_library_item(organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_library",
         "create-library-item",
         params
       ),
       do: create_library_item(scope, organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_library",
         "add-library-version",
         params
       ),
       do: add_library_version(scope, organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_playlists",
         "create-playlist",
         params
       ),
       do: create_playlist(scope, organization_id, mission_id, params)

  defp dispatch(
         _scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_playlist_present",
         "next-dashboard",
         params
       ),
       do: next_dashboard(organization_id, mission_id, params)

  defp dispatch(
         _scope,
         _host_context,
         _organization_id,
         _mission_id,
         "dashboard_settings",
         "validate-settings",
         params
       ),
       do: validate_settings(params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_settings",
         "save-settings",
         params
       ),
       do: save_settings(scope, organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_settings",
         "create-share",
         params
       ),
       do: create_share(scope, organization_id, mission_id, params)

  defp dispatch(
         _scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_settings",
         "revoke-share",
         params
       ),
       do: revoke_share(organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_settings",
         "create-snapshot",
         params
       ),
       do: create_snapshot(scope, organization_id, mission_id, params)

  defp dispatch(
         scope,
         _host_context,
         organization_id,
         mission_id,
         "dashboard_settings",
         "archive-dashboard",
         params
       ),
       do: archive_dashboard(scope, organization_id, mission_id, params)

  defp dispatch(
         _scope,
         _host_context,
         _organization_id,
         _mission_id,
         _surface_id,
         _action_id,
         _params
       ),
       do: {:error, :unsupported_application_action}

  defp filter_dashboards(organization_id, mission_id, params) do
    with {:ok, directory} <- action_map(params, "directory", [], @filter_keys),
         {:ok, query} <- filter_text(directory, "query", ""),
         {:ok, lifecycle} <-
           filter_enum(directory, "lifecycle", ~w(active archived all), "active"),
         {:ok, tag} <- filter_tag(directory),
         {:ok, sort} <- filter_enum(directory, "sort", ~w(updated name widgets), "updated") do
      filters = %{"query" => query, "lifecycle" => lifecycle, "tag" => tag, "sort" => sort}

      rows =
        organization_id
        |> Dashboards.list_dashboard_summaries(mission_id)
        |> Enum.filter(&dashboard_matches?(&1, filters))
        |> Enum.sort_by(&dashboard_sort_key(&1, sort))

      {:ok,
       %{
         "filters" => filters,
         "props" => %{
           "filters" => %{"values" => filters},
           "dashboard_directory" => Enum.map(rows, &presentation_dashboard_row/1)
         }
       }}
    end
  end

  defp dashboard_matches?(summary, filters) do
    query = filters["query"]
    lifecycle = filters["lifecycle"]
    tag = filters["tag"]
    name = String.downcase(to_string(summary.name))

    (query == "" or String.contains?(name, String.downcase(query))) and
      lifecycle in ["all", "active"] and
      (tag == "" or tag in List.wrap(Map.get(summary, :tags, [])))
  end

  defp dashboard_sort_key(summary, "name"),
    do: {String.downcase(to_string(summary.name)), summary.dashboard_id}

  defp dashboard_sort_key(summary, "widgets"), do: {summary.latest_version, summary.dashboard_id}
  defp dashboard_sort_key(summary, _sort), do: {summary.latest_version, summary.dashboard_id}

  defp presentation_dashboard_row(summary) do
    dashboard_id = summary.dashboard_id

    %{
      "id" => dashboard_id,
      "__dom_id" => "dashboard-#{dashboard_id}",
      "dashboard_id" => dashboard_id,
      "name" => summary.name,
      "description" => summary.description,
      "tags" => List.wrap(Map.get(summary, :tags, [])),
      "lifecycle" => %{"state" => "active", "class" => "badge-success"},
      "starred" => false,
      "open" => %{"id" => "open-#{dashboard_id}", "href" => "#"},
      "star" => %{
        "id" => "star-#{dashboard_id}",
        "payload" => %{"dashboard-id" => dashboard_id, "starred" => "true"},
        "aria_label" => "Star dashboard",
        "aria_pressed" => "false",
        "disabled" => false,
        "title" => "Star dashboard",
        "icon" => "hero-star"
      },
      "widget_version_label" => "v#{summary.latest_version}",
      "clone" => nil,
      "restore" => nil
    }
  end

  defp toggle_dashboard_star(scope, organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["dashboard-id", "starred"], ["mission_id", "dashboard_id"]),
         {:ok, dashboard_id} <- identity_param(params, "dashboard_id", "dashboard-id"),
         {:ok, starred} <- boolean_param(params, "starred"),
         {:ok, user_id} <- current_user_id(scope),
         {:ok, preference} <-
           Dashboards.set_dashboard_starred(
             organization_id,
             mission_id,
             user_id,
             dashboard_id,
             starred
           ) do
      {:ok, %{"dashboardId" => dashboard_id, "starred" => preference.starred}}
    end
  end

  defp restore_dashboard(scope, organization_id, mission_id, params) do
    with :ok <-
           exact_keys(params, ["dashboard-id"], ["expected-version", "mission_id", "dashboard_id"]),
         {:ok, dashboard_id} <- identity_param(params, "dashboard_id", "dashboard-id"),
         {:ok, summary} <- restore_summary(organization_id, mission_id, dashboard_id),
         {:ok, expected_version} <-
           optional_version(params, "expected-version", summary.latest_version),
         :ok <-
           Dashboards.restore_document(
             organization_id,
             mission_id,
             dashboard_id,
             expected_version: expected_version,
             actor_id: current_user_id_or_nil(scope)
           ) do
      {:ok, %{"dashboardId" => dashboard_id, "lifecycleState" => "active"}}
    end
  end

  defp validate_dashboard(params) do
    with :ok <- exact_keys(params, ["dashboard"], ["mission_id", "mode", "source_dashboard_id"]),
         {:ok, dashboard} <- action_map(params, "dashboard", [], @new_dashboard_keys),
         {:ok, form} <- form_fields(dashboard, @new_dashboard_keys) do
      {:ok, %{"dashboard" => form}}
    end
  end

  defp save_dashboard(scope, organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["dashboard"], ["mission_id", "mode", "source_dashboard_id"]),
         {:ok, dashboard} <- action_map(params, "dashboard", ["name"], @new_dashboard_keys),
         {:ok, name} <- required_text(dashboard, "name", "Name is required."),
         {:ok, description} <- normalized_optional_text(dashboard, "description"),
         {:ok, mode} <- creation_mode(params),
         {:ok, persisted} <-
           persist_dashboard(
             scope,
             organization_id,
             mission_id,
             mode,
             params,
             dashboard,
             name,
             description
           ) do
      {:ok,
       %{
         "dashboardId" => persisted.dashboard_id,
         "dashboardVersion" => Document.version(persisted),
         "mode" => mode
       }}
    end
  end

  defp persist_dashboard(
         scope,
         organization_id,
         mission_id,
         "new",
         _params,
         _dashboard,
         name,
         description
       ) do
    document = %Document{
      dashboard_id: Cadence.Ids.new("ops_dashboard"),
      organization_id: organization_id,
      mission_id: mission_id,
      name: name,
      description: description,
      metadata: %{
        "source" => "ops_dashboard_new_live",
        "created_by" => current_user_id_or_nil(scope)
      }
    }

    Dashboards.persist_document(organization_id, document)
  end

  defp persist_dashboard(
         scope,
         organization_id,
         mission_id,
         "clone",
         params,
         _dashboard,
         name,
         description
       ) do
    with {:ok, source_dashboard_id} <- required_identity(params, "source_dashboard_id"),
         {:ok, document} <-
           Dashboards.clone_document(
             organization_id,
             mission_id,
             source_dashboard_id,
             name: name,
             description: description,
             actor_id: current_user_id_or_nil(scope)
           ) do
      {:ok, document}
    end
  end

  defp persist_dashboard(
         scope,
         organization_id,
         mission_id,
         "import",
         _params,
         dashboard,
         name,
         description
       ) do
    with {:ok, document_json} <-
           required_json_text(dashboard, "document_json", "Dashboard JSON is required."),
         {:ok, document} <-
           Dashboards.import_document(
             organization_id,
             mission_id,
             document_json,
             name: name,
             description: description,
             actor_id: current_user_id_or_nil(scope)
           ) do
      {:ok, document}
    end
  end

  defp stage_library_item(organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["library_add"], ["mission_id"]),
         {:ok, add} <-
           action_map(params, "library_add", ["dashboard_id", "item_id", "version"], []),
         {:ok, dashboard_id} <- required_identity(add, "dashboard_id"),
         {:ok, item_id} <- required_identity(add, "item_id"),
         {:ok, version} <- required_version(add, "version"),
         true <- dashboard_exists?(organization_id, mission_id, dashboard_id),
         {:ok, _library_version} <-
           Management.fetch_library_version(organization_id, mission_id, item_id, version) do
      {:ok,
       %{"dashboardId" => dashboard_id, "libraryItemId" => item_id, "libraryVersion" => version}}
    else
      false ->
        {:error, :dashboard_not_found}

      {:error, :dashboard_library_version_not_found} ->
        {:error, :dashboard_library_version_not_found}

      _invalid ->
        {:error, :invalid_dashboard_library_stage}
    end
  end

  defp create_library_item(scope, organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["library_item"], ["mission_id"]),
         {:ok, item} <-
           action_map(
             params,
             "library_item",
             ["name", "widget_json"],
             @library_item_optional_keys
           ),
         {:ok, widget_definition} <-
           json_object(item, "widget_json", "Widget definition must be a JSON object."),
         {:ok, name} <- field_string(item, "name"),
         {:ok, description} <- field_string(item, "description"),
         {:ok, change_summary} <- optional_text(item, "change_summary"),
         {:ok, created} <-
           Management.create_library_item(
             organization_id,
             mission_id,
             %{
               "name" => name,
               "description" => description,
               "change_summary" => change_summary,
               "widget_definition" => widget_definition
             },
             created_by: current_user_id_or_nil(scope)
           ) do
      {:ok,
       %{
         "libraryItemId" => created.dashboard_library_item_id,
         "latestVersion" => created.latest_version
       }}
    end
  end

  defp add_library_version(scope, organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["library_version"], ["mission_id"]),
         {:ok, version_params} <-
           action_map(params, "library_version", ["item_id", "widget_json"], ["change_summary"]),
         {:ok, item_id} <- required_identity(version_params, "item_id"),
         {:ok, widget_definition} <-
           json_object(version_params, "widget_json", "Widget definition must be a JSON object."),
         {:ok, change_summary} <- optional_text(version_params, "change_summary"),
         {:ok, updated} <-
           Management.add_library_version(
             organization_id,
             mission_id,
             item_id,
             widget_definition,
             created_by: current_user_id_or_nil(scope),
             change_summary: change_summary || "Updated reusable widget"
           ) do
      {:ok,
       %{
         "libraryItemId" => updated.dashboard_library_item_id,
         "latestVersion" => updated.latest_version
       }}
    end
  end

  defp create_playlist(scope, organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["playlist"], ["mission_id"]),
         {:ok, playlist_params} <-
           action_map(params, "playlist", ["name", "dashboard_ids"], [
             "description",
             "dwell_seconds",
             "wallboard_mode"
           ]),
         {:ok, name} <- field_string(playlist_params, "name"),
         {:ok, description} <- field_string(playlist_params, "description"),
         {:ok, dashboard_ids} <- dashboard_ids(playlist_params),
         {:ok, dwell_seconds} <- optional_integer(playlist_params, "dwell_seconds", 30),
         {:ok, wallboard_mode} <- boolean_value(playlist_params, "wallboard_mode", false),
         {:ok, playlist} <-
           Management.create_playlist(
             organization_id,
             mission_id,
             %{
               "name" => name,
               "description" => description,
               "dashboard_ids" => dashboard_ids,
               "dwell_seconds" => dwell_seconds,
               "wallboard_mode" => wallboard_mode
             },
             created_by: current_user_id_or_nil(scope)
           ) do
      {:ok, playlist_result(playlist)}
    end
  end

  defp next_dashboard(organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["playlist_id"], ["index", "mission_id", "playlist-id"]),
         {:ok, playlist_id} <- identity_param(params, "playlist_id", "playlist-id"),
         {:ok, index} <- nonnegative_integer(params, "index", 0),
         {:ok, %DashboardPlaylist{} = playlist} <-
           Management.fetch_playlist(organization_id, mission_id, playlist_id),
         true <- playlist.dashboard_ids != [] do
      next_index = rem(index + 1, length(playlist.dashboard_ids))
      {:ok, %{"playlistId" => playlist_id, "index" => next_index}}
    else
      false -> {:error, :dashboard_playlist_empty}
      {:error, :dashboard_playlist_not_found} -> {:error, :dashboard_playlist_not_found}
      _invalid -> {:error, :invalid_dashboard_playlist_context}
    end
  end

  defp validate_settings(params) do
    with :ok <- exact_keys(params, ["settings"], ["mission_id"]),
         {:ok, settings} <- action_map(params, "settings", [], @settings_keys),
         {:ok, form} <- form_fields(settings, @settings_keys) do
      {:ok, %{"settings" => form}}
    end
  end

  defp save_settings(scope, organization_id, mission_id, params) do
    with :ok <-
           exact_keys(params, ["settings"], [
             "dashboard_id",
             "dashboard-id",
             "expected_version",
             "expected-version",
             "runtime_context",
             "mission_id"
           ]),
         {:ok, dashboard_id} <- identity_param(params, "dashboard_id", "dashboard-id"),
         {:ok, settings} <- action_map(params, "settings", ["name"], @settings_keys),
         {:ok, name} <- required_text(settings, "name", "Name is required."),
         {:ok, description} <- normalized_optional_text(settings, "description"),
         {:ok, defaults_json} <- field_string(settings, "defaults_json"),
         {:ok, defaults} <- decode_object(defaults_json, "Runtime defaults contain invalid JSON."),
         {:ok, tags} <- field_string(settings, "tags"),
         {:ok, current} <-
           Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit),
         {:ok, expected_version} <-
           optional_alias_version(
             params,
             "expected_version",
             "expected-version",
             Document.version(current)
           ),
         document <- settings_document(current, name, description, defaults, tags),
         {:ok, persisted} <-
           Dashboards.update_document(
             organization_id,
             mission_id,
             dashboard_id,
             document,
             expected_version: expected_version,
             created_by: current_user_id_or_nil(scope),
             change_summary: "Updated dashboard settings"
           ) do
      {:ok, document_result(persisted)}
    end
  end

  defp create_share(scope, organization_id, mission_id, params) do
    with :ok <-
           exact_keys(params, ["share"], [
             "dashboard_id",
             "dashboard-id",
             "runtime_context",
             "mission_id"
           ]),
         {:ok, dashboard_id} <- identity_param(params, "dashboard_id", "dashboard-id"),
         {:ok, share} <- action_map(params, "share", [], ["data_visibility", "expires_in_hours"]),
         {:ok, data_visibility} <- visibility(share),
         {:ok, expires_in_hours} <- optional_integer(share, "expires_in_hours", nil),
         {:ok, runtime_context} <- runtime_context(params),
         {:ok, created} <-
           Management.create_share(
             organization_id,
             mission_id,
             dashboard_id,
             runtime_context,
             created_by: current_user_id_or_nil(scope),
             data_visibility: data_visibility,
             expires_in_hours: expires_in_hours
           ) do
      {:ok, share_result(created)}
    end
  end

  defp revoke_share(organization_id, mission_id, params) do
    with :ok <- exact_keys(params, ["share-id"], ["mission_id"]),
         {:ok, share_id} <- required_identity(params, "share-id"),
         {:ok, revoked} <- Management.revoke_share(organization_id, mission_id, share_id) do
      {:ok, share_result(revoked)}
    end
  end

  defp create_snapshot(scope, organization_id, mission_id, params) do
    with :ok <-
           exact_keys(params, ["snapshot"], [
             "dashboard_id",
             "dashboard-id",
             "runtime_context",
             "mission_id"
           ]),
         {:ok, dashboard_id} <- identity_param(params, "dashboard_id", "dashboard-id"),
         {:ok, snapshot_params} <- action_map(params, "snapshot", [], ["data_visibility"]),
         {:ok, data_visibility} <- visibility(snapshot_params),
         {:ok, runtime_context} <- runtime_context(params),
         {:ok, document} <-
           Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit),
         {:ok, snapshot} <-
           Management.create_snapshot(
             organization_id,
             mission_id,
             document,
             runtime_context,
             created_by: current_user_id_or_nil(scope),
             data_visibility: data_visibility
           ) do
      {:ok, snapshot_result(snapshot)}
    end
  end

  defp archive_dashboard(scope, organization_id, mission_id, params) do
    with :ok <-
           exact_keys(params, [], [
             "dashboard_id",
             "dashboard-id",
             "expected_version",
             "expected-version",
             "mission_id"
           ]),
         {:ok, dashboard_id} <- identity_param(params, "dashboard_id", "dashboard-id"),
         {:ok, current} <-
           Dashboards.fetch_document_for_mode(organization_id, mission_id, dashboard_id, :edit),
         {:ok, expected_version} <-
           optional_alias_version(
             params,
             "expected_version",
             "expected-version",
             Document.version(current)
           ),
         :ok <-
           Dashboards.archive_document(
             organization_id,
             mission_id,
             dashboard_id,
             expected_version: expected_version,
             actor_id: current_user_id_or_nil(scope)
           ) do
      {:ok, %{"dashboardId" => dashboard_id, "lifecycleState" => "archived"}}
    end
  end

  defp validate_binding(surface_id, action_id) do
    if {surface_id, action_id} in @bindings,
      do: :ok,
      else: {:error, :unsupported_application_action}
  end

  defp validate_host_context(%HostContext{} = host_context) do
    if HostContext.valid?(host_context), do: :ok, else: {:error, :unsupported_application_action}
  end

  defp validate_params(params) do
    case JSONBoundary.validate(params) do
      :ok ->
        :ok

      {:error, _reason} ->
        {:error, invalid_input(nil, "Action input is outside the JSON boundary.")}
    end
  end

  defp validate_mission_param(mission_id, params) do
    case Map.get(params, "mission_id") do
      nil -> :ok
      ^mission_id -> :ok
      value when is_binary(value) -> {:error, :scope_mismatch}
      _value -> {:error, invalid_input("mission_id", "Mission context is invalid.")}
    end
  end

  defp authorize(scope, organization_id, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  defp action_map(params, key, required, optional) do
    case Map.get(params, key) do
      map when is_map(map) ->
        with :ok <- exact_keys(map, required, optional), do: {:ok, map}

      _value ->
        {:error, invalid_input(key, "Expected an object for #{key}.")}
    end
  end

  defp exact_keys(map, required, optional) when is_map(map) do
    keys = Map.keys(map)

    if Enum.all?(keys, &is_binary/1) and Enum.all?(keys, &(&1 in (required ++ optional))) and
         Enum.all?(required, &Map.has_key?(map, &1)) do
      :ok
    else
      {:error, invalid_input(nil, "Action input contains unknown or missing fields.")}
    end
  end

  defp exact_keys(_map, _required, _optional),
    do: {:error, invalid_input(nil, "Action input must be a JSON object.")}

  defp form_fields(map, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case field_string(map, field) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp field_string(map, field) do
    case Map.get(map, field, "") do
      value when is_binary(value) -> {:ok, value}
      _value -> {:error, invalid_input(field, "Expected text input.")}
    end
  end

  defp required_text(map, field, message) do
    with {:ok, value} <- optional_text(map, field) do
      case value do
        nil -> {:error, invalid_input(field, message)}
        value -> {:ok, value}
      end
    end
  end

  defp required_identity(map, field) do
    with {:ok, value} <- identity_value(Map.get(map, field)) do
      {:ok, value}
    end
  end

  defp identity_param(map, primary, alternate) do
    case {Map.get(map, primary), Map.get(map, alternate)} do
      {nil, nil} -> {:error, invalid_input(primary, "An identifier is required.")}
      {value, nil} -> identity_value(value)
      {nil, value} -> identity_value(value)
      {left, right} when left == right -> identity_value(left)
      _different -> {:error, :scope_mismatch}
    end
  end

  defp identity_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, invalid_input(nil, "An identifier is required.")}
      value -> {:ok, value}
    end
  end

  defp identity_value(_value), do: {:error, invalid_input(nil, "An identifier is invalid.")}

  defp optional_text(map, field) do
    case Map.fetch(map, field) do
      :error ->
        {:ok, nil}

      {:ok, value} when is_binary(value) ->
        case String.trim(value) do
          "" -> {:ok, nil}
          value -> {:ok, value}
        end

      {:ok, _value} ->
        {:error, invalid_input(field, "Expected text input.")}
    end
  end

  defp normalized_optional_text(map, field) do
    optional_text(map, field)
  end

  defp required_json_text(map, field, message) do
    with {:ok, value} <- field_string(map, field) do
      if value == "", do: {:error, invalid_input(field, message)}, else: {:ok, value}
    end
  end

  defp json_object(map, field, message) do
    with {:ok, value} <- required_json_text(map, field, message),
         {:ok, decoded} <- decode_object(value, message) do
      {:ok, decoded}
    end
  end

  defp decode_object(value, message) do
    if is_binary(value) do
      case Jason.decode(value) do
        {:ok, decoded} when is_map(decoded) ->
          case JSONBoundary.validate(decoded) do
            :ok -> {:ok, decoded}
            {:error, _reason} -> {:error, invalid_input(nil, message)}
          end

        _invalid ->
          {:error, invalid_input(nil, message)}
      end
    else
      {:error, invalid_input(nil, message)}
    end
  end

  defp boolean_value(map, field, default) do
    case Map.get(map, field, default) do
      value when is_boolean(value) -> {:ok, value}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      "on" -> {:ok, true}
      "1" -> {:ok, true}
      "0" -> {:ok, false}
      nil -> {:ok, default}
      _value -> {:error, invalid_input(field, "Expected a boolean input.")}
    end
  end

  defp optional_integer(map, field, default) do
    case Map.get(map, field, default) do
      nil ->
        {:ok, nil}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> {:ok, integer}
          _invalid -> {:error, invalid_input(field, "Expected a positive integer.")}
        end

      _value ->
        {:error, invalid_input(field, "Expected a positive integer.")}
    end
  end

  defp nonnegative_integer(map, field, default) do
    case Map.get(map, field, default) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _invalid -> {:error, invalid_input(field, "Expected a non-negative integer.")}
        end

      _value ->
        {:error, invalid_input(field, "Expected a non-negative integer.")}
    end
  end

  defp required_version(map, field) do
    case optional_integer(map, field, nil) do
      {:ok, nil} -> {:error, invalid_input(field, "A positive version is required.")}
      result -> result
    end
  end

  defp optional_version(map, field, default) do
    case Map.has_key?(map, field) do
      true -> optional_integer(map, field, default)
      false -> {:ok, default}
    end
  end

  defp optional_alias_version(map, primary, alternate, default) do
    case {Map.has_key?(map, primary), Map.has_key?(map, alternate)} do
      {false, false} ->
        {:ok, default}

      {true, false} ->
        optional_integer(map, primary, default)

      {false, true} ->
        optional_integer(map, alternate, default)

      {true, true} ->
        if Map.get(map, primary) == Map.get(map, alternate) do
          optional_integer(map, primary, default)
        else
          {:error, :scope_mismatch}
        end
    end
  end

  defp creation_mode(params) do
    case Map.get(params, "mode", "new") do
      mode when mode in ["new", "clone", "import"] -> {:ok, mode}
      _invalid -> {:error, invalid_input("mode", "Dashboard creation mode is invalid.")}
    end
  end

  defp dashboard_ids(map) do
    case Map.get(map, "dashboard_ids", []) do
      ids when is_list(ids) ->
        if Enum.all?(ids, &is_binary/1) do
          {:ok, ids}
        else
          {:error, invalid_input("dashboard_ids", "Dashboard references must be a list.")}
        end

      _invalid ->
        {:error, invalid_input("dashboard_ids", "Dashboard references must be a list.")}
    end
  end

  defp visibility(map) do
    case Map.get(map, "data_visibility", "authorized_runtime_data") do
      value when value in ["authorized_runtime_data", "definition_only"] -> {:ok, value}
      _invalid -> {:error, invalid_input("data_visibility", "Data visibility is invalid.")}
    end
  end

  defp runtime_context(params) do
    case Map.get(params, "runtime_context", %{}) do
      context when is_map(context) -> {:ok, Management.normalize_runtime_context(context)}
      _invalid -> {:error, invalid_input("runtime_context", "Runtime context must be an object.")}
    end
  end

  defp restore_summary(organization_id, mission_id, dashboard_id) do
    summaries =
      Dashboards.list_dashboard_summaries(organization_id, mission_id) ++
        Dashboards.list_archived_dashboard_summaries(organization_id, mission_id)

    case Enum.find(summaries, &(&1.dashboard_id == dashboard_id)) do
      nil ->
        {:error, :dashboard_not_found}

      summary ->
        if Dashboards.dashboard_lifecycle_status(summary).restore_available?,
          do: {:ok, summary},
          else: {:error, :dashboard_restore_not_available}
    end
  end

  defp dashboard_exists?(organization_id, mission_id, dashboard_id) do
    Enum.any?(
      Dashboards.list_dashboard_summaries(organization_id, mission_id),
      &(&1.dashboard_id == dashboard_id)
    )
  end

  defp settings_document(%Document{} = document, name, description, defaults, tags) do
    metadata =
      if(is_map(document.metadata), do: document.metadata, else: %{})
      |> Map.delete(:tags)
      |> Map.put("tags", normalize_tags(tags))

    %Document{
      document
      | name: name,
        description: description,
        defaults: defaults,
        metadata: metadata
    }
  end

  defp normalize_tags(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp current_user_id(%Scope{user: %{user_id: user_id}}) when is_binary(user_id),
    do: {:ok, user_id}

  defp current_user_id(%Scope{}),
    do: {:error, invalid_input(nil, "A signed-in user is required.")}

  defp current_user_id_or_nil(%Scope{user: %{user_id: user_id}}) when is_binary(user_id),
    do: user_id

  defp current_user_id_or_nil(%Scope{}), do: nil

  defp document_result(%Document{} = document) do
    %{
      "dashboardId" => document.dashboard_id,
      "dashboardVersion" => Document.version(document),
      "name" => document.name
    }
  end

  defp share_result(share) do
    %{
      "shareId" => share.dashboard_share_id,
      "dashboardId" => share.dashboard_id,
      "status" => if(is_nil(share.revoked_at), do: "active", else: "revoked")
    }
  end

  defp snapshot_result(snapshot) do
    %{
      "snapshotId" => snapshot.dashboard_snapshot_id,
      "dashboardId" => snapshot.dashboard_id,
      "dashboardVersion" => snapshot.dashboard_version
    }
  end

  defp playlist_result(%DashboardPlaylist{} = playlist) do
    %{
      "playlistId" => playlist.dashboard_playlist_id,
      "name" => playlist.name,
      "dashboardIds" => playlist.dashboard_ids,
      "dwellSeconds" => playlist.dwell_seconds,
      "wallboardMode" => playlist.wallboard_mode
    }
  end

  defp filter_text(map, field, default) do
    case Map.get(map, field, default) do
      value when is_binary(value) -> {:ok, String.trim(value)}
      _value -> {:error, invalid_input(field, "Filter values must be text.")}
    end
  end

  defp filter_enum(map, field, allowed, default) do
    case Map.get(map, field, default) do
      value when is_binary(value) ->
        if value in allowed, do: {:ok, value}, else: {:ok, default}

      _value ->
        {:error, invalid_input(field, "Filter values must be text.")}
    end
  end

  defp filter_tag(map) do
    case Map.get(map, "tag", "all") do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:ok, "all"}
          value -> {:ok, value}
        end

      _value ->
        {:error, invalid_input("tag", "Filter values must be text.")}
    end
  end

  defp boolean_param(map, field) do
    case Map.get(map, field) do
      value when is_boolean(value) -> {:ok, value}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _value -> {:error, invalid_input(field, "Expected a boolean input.")}
    end
  end

  defp invalid_input(field, message),
    do: %ActionFailure{code: "invalid_action_input", message: message, field: field}
end
