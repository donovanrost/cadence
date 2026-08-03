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
    socket =
      socket
      |> stream_configure(:library_items,
        dom_id: &"dashboard-library-item-#{&1.item.dashboard_library_item_id}"
      )
      |> assign(:page_title, "Dashboard Library")
      |> assign(:ops_nav_item, :dashboards)
      |> assign(:active_dashboard_id, nil)
      |> assign(:library_create_form, library_create_form())
      |> assign(:library_version_form, library_version_form())
      |> assign(:library_add_form, library_add_form())
      |> assign(:dashboard_options, [])
      |> assign(:library_version_options, [])
      |> stream(:library_items, [])
      |> reload_library()

    {:ok, socket}
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
       |> assign(:library_create_form, library_create_form())
       |> reload_library()
       |> put_flash(:info, "Reusable widget created at version 1.")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create library item: #{error_text(reason)}")}
    end
  end

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

  def handle_event("stage_library_item", %{"library_add" => params}, socket) do
    with item_id when is_binary(item_id) <- present(params["item_id"]),
         {version, ""} <- Integer.parse(params["version"] || ""),
         dashboard_id when is_binary(dashboard_id) <- present(params["dashboard_id"]) do
      mission_id = socket.assigns.current_mission.mission_id

      {:noreply,
       push_navigate(socket,
         to:
           ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/edit?#{[candidate_source: "library", candidate_library_item_id: item_id, candidate_library_version: version]}"
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
      <section id="dashboard-library-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-6 py-5 hud-grid">
          <div class="mx-auto max-w-6xl">
            <p class="hud-label">Dashboards / Library</p>
            <h1 class="mt-1 text-2xl font-semibold">Reusable widget library</h1>
            <p class="mt-2 max-w-3xl text-sm text-base-content/60">
              Every consumer pins an immutable version. New versions expose update posture but never rewrite a dashboard.
            </p>
          </div>
        </header>

        <div class="mx-auto grid max-w-6xl gap-5 p-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div id="dashboard-library-list" phx-update="stream" class="space-y-3">
            <div id="dashboard-library-empty" class="hidden only:block border border-dashed border-base-300 p-8 text-center text-sm text-base-content/50">No reusable widgets yet.</div>
            <article :for={{id, entry} <- @streams.library_items} id={id} class="border border-base-300 bg-base-200/20 p-4">
              <div class="flex items-start justify-between gap-3">
                <div><h2 class="font-semibold">{entry.item.name}</h2><p class="mt-1 text-xs text-base-content/55">{entry.item.description}</p></div>
                <span class="badge badge-outline font-mono">v{entry.item.latest_version}</span>
              </div>
              <dl class="mt-4 grid grid-cols-3 gap-2 text-xs">
                <div><dt class="hud-label">Consumers</dt><dd class="mt-1 text-lg">{entry.usage.consumer_count}</dd></div>
                <div><dt class="hud-label">Updates</dt><dd class="mt-1 text-lg text-warning">{entry.usage.outdated_count}</dd></div>
                <div><dt class="hud-label">Compatibility</dt><dd class="mt-1 font-mono">{entry.compatibility["widget_type_id"] || "unknown"}</dd></div>
              </dl>
              <div class="mt-3 flex flex-wrap gap-1">
                <span :for={version <- entry.versions} id={"library-version-#{version.dashboard_library_version_id}"} class="badge badge-ghost font-mono">v{version.version}</span>
              </div>
            </article>
          </div>

          <aside class="space-y-4">
            <.form for={@library_add_form} id="dashboard-library-add-form" phx-submit="stage_library_item" class="space-y-3 border border-primary/30 bg-primary/5 p-4">
              <p class="hud-label">Use exact version</p>
              <.input field={@library_add_form[:dashboard_id]} type="select" label="Dashboard" options={[{"Choose dashboard", ""} | @dashboard_options]} />
              <.input field={@library_add_form[:item_id]} type="select" label="Library item" options={[{"Choose item", ""} | Enum.map(@library_version_options, fn {label, item_id, _version} -> {label, item_id} end)]} />
              <.input field={@library_add_form[:version]} type="number" label="Pinned version" min="1" />
              <.button id="dashboard-library-stage" type="submit">Stage in Editor</.button>
            </.form>

            <details open class="border border-base-300 bg-base-200/20 p-4">
              <summary class="cursor-pointer font-semibold">Create library item</summary>
              <.form for={@library_create_form} id="dashboard-library-create-form" phx-submit="create_library_item" class="mt-4 space-y-3">
                <.input field={@library_create_form[:name]} type="text" label="Name" required />
                <.input field={@library_create_form[:description]} type="textarea" label="Description" />
                <.input field={@library_create_form[:change_summary]} type="text" label="Version note" />
                <.input field={@library_create_form[:widget_json]} type="textarea" label="Widget definition JSON" class="textarea textarea-bordered min-h-72 w-full font-mono text-xs" />
                <.button id="dashboard-library-create" type="submit">Create version 1</.button>
              </.form>
            </details>

            <details class="border border-base-300 bg-base-200/20 p-4">
              <summary class="cursor-pointer font-semibold">Add immutable version</summary>
              <.form for={@library_version_form} id="dashboard-library-version-form" phx-submit="add_library_version" class="mt-4 space-y-3">
                <.input field={@library_version_form[:item_id]} type="select" label="Library item" options={[{"Choose item", ""} | Enum.map(@library_version_options, fn {label, item_id, _version} -> {label, item_id} end)]} />
                <.input field={@library_version_form[:change_summary]} type="text" label="Change summary" />
                <.input field={@library_version_form[:widget_json]} type="textarea" label="Widget definition JSON" class="textarea textarea-bordered min-h-72 w-full font-mono text-xs" />
                <.button id="dashboard-library-add-version" type="submit">Create next version</.button>
              </.form>
            </details>
          </aside>
        </div>
      </section>
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

        %{
          id: item.dashboard_library_item_id,
          item: item,
          versions: versions,
          compatibility: if(latest, do: latest.compatibility, else: %{}),
          usage: Management.library_usage(scope.organization_id, mission.mission_id, item)
        }
      end)

    dashboard_options =
      scope.organization_id
      |> Cadence.Dashboards.list_dashboard_summaries(mission.mission_id)
      |> Enum.map(&{&1.name, &1.dashboard_id})

    library_options =
      Enum.map(
        items,
        &{"#{&1.name} (latest v#{&1.latest_version})", &1.dashboard_library_item_id,
         &1.latest_version}
      )

    socket
    |> assign(:dashboard_options, dashboard_options)
    |> assign(:library_version_options, library_options)
    |> stream(:library_items, entries, reset: true)
  end

  defp library_create_form do
    to_form(
      %{
        "name" => "",
        "description" => "",
        "change_summary" => "Initial version",
        "widget_json" => @default_widget_json
      },
      as: :library_item
    )
  end

  defp library_version_form do
    to_form(%{"item_id" => "", "change_summary" => "", "widget_json" => @default_widget_json},
      as: :library_version
    )
  end

  defp library_add_form do
    to_form(%{"dashboard_id" => "", "item_id" => "", "version" => "1"}, as: :library_add)
  end

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
