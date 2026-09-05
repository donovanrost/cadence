defmodule CadenceWeb.OpsDashboardLibraryLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Management

  @default_widget_json Jason.encode!(
                         %{
                           "widget_type_id" => "time_series",
                           "widget_type_version" => 1,
                           "title" => "Reusable telemetry trend",
                           "binding" => %{
                             "source" => "telemetry",
                             "observables" => ["telemetry.point"],
                             "scope_mode" => "context",
                             "data_mode" => "context",
                             "sampling" => "raw_series"
                           },
                           "options" => %{}
                         },
                         pretty: true
                       )

  @impl true
  def mount(_params, _session, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    {:ok,
     socket
     |> stream_configure(:library_items,
       dom_id: &"dashboard-library-item-#{&1.item.dashboard_library_item_id}"
     )
     |> assign(:page_title, "Dashboard Library")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:active_dashboard_id, nil)
     |> assign(:library_page, library_page_dto(mission_id))
     |> assign(:library_create_form, library_create_form_dto(0))
     |> assign(:library_version_form, library_version_form_dto())
     |> assign(:library_add_form, library_add_form_dto())
     |> assign(:dashboard_options, [])
     |> assign(:library_options, [])
     |> stream(:library_items, [])
     |> reload_library()}
  end

  @impl true
  def handle_event("create_library_item", %{"library_item" => params}, socket) do
    with {:ok, widget_definition} <- decode_widget(params["widget_json"]),
         %{current_scope: scope, current_mission: mission} <- socket.assigns,
         {:ok, _item} <-
           Management.create_library_item(
             scope.organization_id,
             mission.mission_id,
             Map.put(params, "widget_definition", widget_definition),
             created_by: current_user_id(scope)
           ) do
      {:noreply,
       socket
       |> assign(
         :library_create_form,
         library_create_form_dto(socket.assigns.library_create_form.reset_revision + 1)
       )
       |> reload_library()
       |> put_flash(:info, "Reusable widget created at version 1.")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create library item: #{error_text(reason)}")}
    end
  end

  @impl true
  def handle_event("add_library_version", %{"library_version" => params}, socket) do
    with {:ok, widget_definition} <- decode_widget(params["widget_json"]),
         item_id when is_binary(item_id) <- present(params["item_id"]),
         %{current_scope: scope, current_mission: mission} <- socket.assigns,
         {:ok, item} <-
           Management.add_library_version(
             scope.organization_id,
             mission.mission_id,
             item_id,
             widget_definition,
             created_by: current_user_id(scope),
             change_summary: present(params["change_summary"]) || "Updated reusable widget"
           ) do
      {:noreply,
       socket
       |> reload_library()
       |> put_flash(
         :info,
         "#{item.name} version #{item.latest_version} created. Consumers remain pinned."
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Choose a library item.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add version: #{error_text(reason)}")}
    end
  end

  @impl true
  def handle_event("stage_library_item", %{"library_add" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with item_id when is_binary(item_id) <- present(params["item_id"]),
         {:ok, version} <- parse_version(params["version"]),
         dashboard_id when is_binary(dashboard_id) <- present(params["dashboard_id"]),
         true <- dashboard_option?(socket.assigns.dashboard_options, dashboard_id),
         {:ok, _library_version} <-
           Management.fetch_library_version(
             scope.organization_id,
             mission.mission_id,
             item_id,
             version
           ) do
      {:noreply,
       push_navigate(socket,
         to: editor_path(mission.mission_id, dashboard_id, item_id, version)
       )}
    else
      _invalid ->
        {:noreply, put_flash(socket, :error, "Choose a dashboard and exact library version.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="dashboard-library-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_library"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp reload_library(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    items = Management.list_library_items(scope.organization_id, mission.mission_id)

    entries =
      Enum.map(items, fn item ->
        versions = Management.list_library_versions(item.dashboard_library_item_id)
        latest = List.first(versions)
        usage = Management.library_usage(scope.organization_id, mission.mission_id, item)

        library_item_dto(mission.mission_id, item, versions, latest, usage)
      end)

    dashboard_options =
      scope.organization_id
      |> Cadence.Dashboards.list_dashboard_summaries(mission.mission_id)
      |> Enum.map(&%{label: &1.name, value: &1.dashboard_id})

    library_options = Enum.map(items, &library_option_dto/1)

    socket
    |> assign(:dashboard_options, dashboard_options)
    |> assign(:library_options, library_options)
    |> stream(:library_items, entries, reset: true)
  end

  defp library_page_dto(mission_id) do
    %{
      id: "dashboard-library-page",
      header: %{
        id: "dashboard-library-header",
        eyebrow: "Dashboards / Library",
        heading: "Reusable widget library",
        copy:
          "Every consumer pins an immutable version. New versions expose update posture but never rewrite a dashboard."
      },
      list: %{
        id: "dashboard-library-list",
        empty: %{id: "dashboard-library-empty", copy: "No reusable widgets yet."}
      },
      paths: %{
        dashboards: ~p"/missions/#{mission_id}/ops/dashboards",
        library: ~p"/missions/#{mission_id}/ops/dashboards/library"
      }
    }
  end

  defp library_item_dto(mission_id, item, versions, latest, usage) do
    item_id = item.dashboard_library_item_id

    %{
      item: %{
        dashboard_library_item_id: item_id,
        name: item.name,
        description: item.description || "",
        latest_version: item.latest_version,
        created_by: item.created_by,
        updated_by: item.updated_by
      },
      versions: Enum.map(versions, &library_version_dto/1),
      compatibility: compatibility_dto(latest),
      usage: usage_dto(mission_id, usage),
      details: %{
        id: "dashboard-library-details-#{item_id}",
        summary_id: "dashboard-library-details-summary-#{item_id}",
        summary: "Version and consumer details",
        versions_id: "dashboard-library-versions-#{item_id}",
        consumers_id: "dashboard-library-consumers-#{item_id}",
        consumers_empty_id: "dashboard-library-consumers-empty-#{item_id}"
      }
    }
  end

  defp library_version_dto(version) do
    %{
      dashboard_library_version_id: version.dashboard_library_version_id,
      version: version.version,
      change_summary: version.change_summary || "",
      created_by: version.created_by,
      badge: %{
        id: "library-version-#{version.dashboard_library_version_id}",
        label: "v#{version.version}"
      },
      detail_id: "library-version-detail-#{version.dashboard_library_version_id}"
    }
  end

  defp compatibility_dto(nil) do
    %{widget_type_id: "unknown", widget_type_version: nil, binding_source: nil}
  end

  defp compatibility_dto(version) do
    compatibility = version.compatibility || %{}

    %{
      widget_type_id: compatibility["widget_type_id"] || "unknown",
      widget_type_version: compatibility["widget_type_version"],
      binding_source: compatibility["binding_source"]
    }
  end

  defp usage_dto(mission_id, usage) do
    %{
      consumer_count: usage.consumer_count,
      outdated_count: usage.outdated_count,
      consumers: Enum.map(usage.consumers, &consumer_dto(mission_id, &1))
    }
  end

  defp consumer_dto(mission_id, consumer) do
    %{
      dashboard_id: consumer.dashboard_id,
      dashboard_name: consumer.dashboard_name,
      placement_id: consumer.placement_id,
      version: consumer.version,
      latest_version: consumer.latest_version,
      update_available: consumer.update_available?,
      id: "dashboard-library-consumer-#{consumer.placement_id}",
      action_id: "dashboard-library-consumer-open-#{consumer.placement_id}",
      path: ~p"/missions/#{mission_id}/ops/dashboards/#{consumer.dashboard_id}"
    }
  end

  defp library_option_dto(item) do
    %{
      label: "#{item.name} (latest v#{item.latest_version})",
      value: item.dashboard_library_item_id,
      latest_version: item.latest_version
    }
  end

  defp library_create_form_dto(reset_revision) do
    form =
      form_params(
        %{
          "name" => "",
          "description" => "",
          "change_summary" => "Initial version",
          "widget_json" => @default_widget_json
        },
        :library_item
      )

    %{
      id: "dashboard-library-create-form",
      reset_revision: reset_revision,
      details: %{
        id: "dashboard-library-create-details",
        summary_id: "dashboard-library-create-summary",
        summary: "Create library item",
        open: true
      },
      fields: %{
        name: text_field(form, :library_item, "name", "Name", "text", required: true),
        description: text_field(form, :library_item, "description", "Description", "textarea"),
        change_summary: text_field(form, :library_item, "change_summary", "Version note", "text"),
        widget_json:
          text_field(
            form,
            :library_item,
            "widget_json",
            "Widget definition JSON",
            "textarea"
          )
      },
      action: %{id: "dashboard-library-create", label: "Create version 1"}
    }
  end

  defp library_version_form_dto do
    form =
      form_params(
        %{"item_id" => "", "change_summary" => "", "widget_json" => @default_widget_json},
        :library_version
      )

    %{
      id: "dashboard-library-version-form",
      details: %{
        id: "dashboard-library-version-details",
        summary_id: "dashboard-library-version-summary",
        summary: "Add immutable version",
        open: false
      },
      fields: %{
        item_id: select_field(form, :library_version, "item_id", "Library item", "Choose item"),
        change_summary:
          text_field(form, :library_version, "change_summary", "Change summary", "text"),
        widget_json:
          text_field(
            form,
            :library_version,
            "widget_json",
            "Widget definition JSON",
            "textarea"
          )
      },
      action: %{id: "dashboard-library-add-version", label: "Create next version"}
    }
  end

  defp library_add_form_dto do
    form =
      form_params(
        %{"dashboard_id" => "", "item_id" => "", "version" => "1"},
        :library_add
      )

    %{
      id: "dashboard-library-add-form",
      eyebrow: "Use exact version",
      fields: %{
        dashboard_id:
          select_field(form, :library_add, "dashboard_id", "Dashboard", "Choose dashboard"),
        item_id: select_field(form, :library_add, "item_id", "Library item", "Choose item"),
        version:
          form
          |> text_field(:library_add, "version", "Pinned version", "number")
          |> Map.put(:min, 1)
      },
      action: %{id: "dashboard-library-stage", label: "Stage in Editor"}
    }
  end

  defp form_params(params, as) do
    form = to_form(params, as: as)
    form.params
  end

  defp text_field(params, form_name, key, label, type, opts \\ []) do
    %{
      id: "#{form_name}_#{key}",
      name: "#{form_name}[#{key}]",
      type: type,
      label: label,
      value: string_param(params, key),
      required: Keyword.get(opts, :required, false)
    }
  end

  defp select_field(params, form_name, key, label, placeholder) do
    params
    |> text_field(form_name, key, label, "select")
    |> Map.put(:placeholder, placeholder)
  end

  defp string_param(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp dashboard_option?(options, dashboard_id) do
    Enum.any?(options, &(&1.value == dashboard_id))
  end

  defp editor_path(mission_id, dashboard_id, item_id, version) do
    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/edit?#{[candidate_source: "library", candidate_library_item_id: item_id, candidate_library_version: version]}"
  end

  defp parse_version(value) when is_binary(value) do
    case Integer.parse(value) do
      {version, ""} when version > 0 -> {:ok, version}
      _invalid -> :error
    end
  end

  defp parse_version(_value), do: :error

  defp decode_widget(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, widget} when is_map(widget) -> {:ok, widget}
      _invalid -> {:error, "Widget definition must be a JSON object."}
    end
  end

  defp decode_widget(_value), do: {:error, "Widget definition must be a JSON object."}

  defp present(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp present(_value), do: nil
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)
  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
