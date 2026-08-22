defmodule CadenceWeb.OpsDashboardSettingsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{Document, Management}

  @impl true
  def mount(%{"dashboard_id" => dashboard_id} = params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.Dashboards.fetch_document_for_mode(
           scope.organization_id,
           mission.mission_id,
           dashboard_id,
           :edit
         ) do
      {:ok, %Document{} = document} ->
        {:ok,
         socket
         |> stream_configure(:dashboard_shares,
           dom_id: &"dashboard-share-#{&1.dashboard_share_id}"
         )
         |> stream_configure(:dashboard_snapshots,
           dom_id: &"dashboard-snapshot-#{&1.dashboard_snapshot_id}"
         )
         |> stream_configure(:dashboard_deployments,
           dom_id: &"dashboard-deployment-#{&1.dashboard_deployment_id}"
         )
         |> assign(:page_title, "#{document.name} Settings")
         |> assign(:ops_nav_item, :dashboards)
         |> assign(:active_dashboard_id, dashboard_id)
         |> assign(:dashboard_document, document)
         |> assign(:runtime_context, Management.normalize_runtime_context(params))
         |> assign(:settings_form, settings_form(document))
         |> assign(:share_form, share_form())
         |> assign(:snapshot_form, snapshot_form())
         |> refresh_management()}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Dashboard settings are unavailable: #{inspect(reason)}")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")}
    end
  end

  @impl true
  def handle_event("create_share", %{"share" => params}, socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    opts = [
      created_by: current_user_id(scope),
      data_visibility: params["data_visibility"],
      expires_in_hours: positive_integer(params["expires_in_hours"])
    ]

    case Management.create_share(
           scope.organization_id,
           mission.mission_id,
           document.dashboard_id,
           socket.assigns.runtime_context,
           opts
         ) do
      {:ok, share} ->
        {:noreply,
         socket
         |> refresh_management()
         |> put_flash(:info, "Authenticated mission share created: #{share.dashboard_share_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create share: #{inspect(reason)}")}
    end
  end

  def handle_event("revoke_share", %{"share-id" => share_id}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Management.revoke_share(scope.organization_id, mission.mission_id, share_id) do
      {:ok, _share} ->
        {:noreply, socket |> refresh_management() |> put_flash(:info, "Share revoked.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke share: #{inspect(reason)}")}
    end
  end

  def handle_event("create_snapshot", %{"snapshot" => params}, socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case Management.create_snapshot(
           scope.organization_id,
           mission.mission_id,
           document,
           socket.assigns.runtime_context,
           created_by: current_user_id(scope),
           data_visibility: params["data_visibility"]
         ) do
      {:ok, snapshot} ->
        {:noreply,
         socket
         |> refresh_management()
         |> put_flash(:info, "Read-only snapshot created: #{snapshot.dashboard_snapshot_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create snapshot: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("validate_settings", %{"settings" => params}, socket) do
    {:noreply, assign(socket, :settings_form, to_form(params, as: :settings))}
  end

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    with {:ok, name} <- required_name(params["name"]),
         {:ok, defaults} <- decode_defaults(params["defaults_json"]),
         document <- settings_document(socket.assigns.dashboard_document, params, name, defaults),
         {:ok, %Document{} = persisted} <- persist_settings(socket, document) do
      {:noreply,
       socket
       |> assign(:dashboard_document, persisted)
       |> assign(:settings_form, settings_form(persisted))
       |> put_flash(:info, "Dashboard settings saved as version #{Document.version(persisted)}.")}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, {:dashboard_version_conflict, current_version}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Dashboard changed in another session (version #{current_version}). Reload before saving."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("archive_dashboard", _params, socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case Cadence.Dashboards.archive_document(
           scope.organization_id,
           mission.mission_id,
           document.dashboard_id,
           expected_version: Document.version(document),
           actor_id: current_user_id(scope)
         ) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Dashboard archived.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to archive dashboard: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard-settings-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-5xl items-end justify-between gap-4">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
                Dashboard / Settings
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">{@dashboard_document.name}</h1>
              <p class="mt-2 text-sm text-base-content/60">
                Durable identity, runtime defaults, discovery metadata, and lifecycle posture.
              </p>
            </div>
            <.link
              id="dashboard-settings-viewer"
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_document.dashboard_id}"}
              class="btn btn-ghost btn-sm"
            >
              Back to Viewer
            </.link>
          </div>
        </header>

        <div class="mx-auto grid max-w-5xl gap-5 p-5 lg:grid-cols-[minmax(0,1fr)_18rem] lg:p-7">
          <div class="space-y-5">
          <.form
            for={@settings_form}
            id="dashboard-settings-form"
            phx-change="validate_settings"
            phx-submit="save_settings"
            class="space-y-5 border border-base-300 bg-base-200/20 p-5"
          >
            <.input field={@settings_form[:name]} type="text" label="Name" required />
            <.input field={@settings_form[:description]} type="textarea" label="Description" />
            <.input
              field={@settings_form[:tags]}
              type="text"
              label="Tags"
              placeholder="power, flight, anomaly-response"
            />
            <.input
              field={@settings_form[:defaults_json]}
              type="textarea"
              label="Runtime defaults (JSON)"
              class="textarea textarea-bordered min-h-64 w-full font-mono text-xs"
            />
            <div class="flex justify-end">
              <.button id="dashboard-settings-save" type="submit" variant={:primary}>
                Save Settings
              </.button>
            </div>
          </.form>

          <section id="dashboard-sharing" class="border border-base-300 bg-base-200/20 p-5">
            <p class="hud-label">Permission-aware sharing</p>
            <h2 class="mt-1 text-lg font-semibold">Share this runtime context</h2>
            <p class="mt-1 text-xs text-base-content/55">
              Links require an authenticated member of this mission. Runtime selectors are captured;
              credentials and runtime samples are never embedded.
            </p>
            <.form for={@share_form} id="dashboard-share-form" phx-submit="create_share" class="mt-4 grid gap-3 sm:grid-cols-2">
              <.input field={@share_form[:data_visibility]} type="select" label="Data visibility" options={[{"Authorized runtime data", "authorized_runtime_data"}, {"Definition only", "definition_only"}]} />
              <.input field={@share_form[:expires_in_hours]} type="number" label="Expires in hours" min="1" placeholder="Never" />
              <.button id="dashboard-share-create" type="submit" class="sm:col-span-2">Create authenticated link</.button>
            </.form>
            <div id="dashboard-share-list" phx-update="stream" class="mt-4 space-y-2">
              <p id="dashboard-share-empty" class="hidden only:block text-xs text-base-content/45">No active or revoked links yet.</p>
              <article :for={{id, share} <- @streams.dashboard_shares} id={id} class="flex items-center gap-3 border border-base-300 bg-base-100 p-3 text-xs">
                <div class="min-w-0 flex-1">
                  <.link id={"dashboard-share-open-#{share.dashboard_share_id}"} navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboard-shares/#{share.dashboard_share_id}"} class="font-mono text-primary hover:underline">{share.dashboard_share_id}</.link>
                  <p class="mt-1 text-base-content/50">{share.access_policy} · {share.data_visibility} · {if share.revoked_at, do: "revoked", else: "active"}</p>
                </div>
                <.button :if={is_nil(share.revoked_at)} id={"dashboard-share-revoke-#{share.dashboard_share_id}"} size={:xs} variant={:ghost} phx-click="revoke_share" phx-value-share-id={share.dashboard_share_id}>Revoke</.button>
              </article>
            </div>
          </section>

          <section id="dashboard-snapshots" class="border border-base-300 bg-base-200/20 p-5">
            <p class="hud-label">Read-only snapshots</p>
            <h2 class="mt-1 text-lg font-semibold">Freeze definition and context</h2>
            <.form for={@snapshot_form} id="dashboard-snapshot-form" phx-submit="create_snapshot" class="mt-4 flex items-end gap-3">
              <.input field={@snapshot_form[:data_visibility]} type="select" label="Data visibility" options={[{"Authorized runtime data", "authorized_runtime_data"}, {"Definition only", "definition_only"}]} />
              <.button id="dashboard-snapshot-create" type="submit">Create snapshot</.button>
            </.form>
            <div id="dashboard-snapshot-list" phx-update="stream" class="mt-4 space-y-2">
              <p id="dashboard-snapshot-empty" class="hidden only:block text-xs text-base-content/45">No snapshots yet.</p>
              <article :for={{id, snapshot} <- @streams.dashboard_snapshots} id={id} class="border border-base-300 bg-base-100 p-3 text-xs">
                <.link id={"dashboard-snapshot-open-#{snapshot.dashboard_snapshot_id}"} navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboard-snapshots/#{snapshot.dashboard_snapshot_id}"} class="font-mono text-primary hover:underline">{snapshot.dashboard_snapshot_id}</.link>
                <p class="mt-1 text-base-content/50">Version {snapshot.dashboard_version} · {snapshot.data_semantics} · {snapshot.data_visibility}</p>
              </article>
            </div>
          </section>
          </div>

          <aside class="space-y-4">
            <section class="border border-primary/30 bg-primary/5 p-4">
              <p class="hud-label">Governed portability</p>
              <p class="mt-2 text-xs text-base-content/60">
                Export includes an integrity digest over binding semantics and records the artifact.
                Import replaces source identity with the target mission.
              </p>
              <a id="dashboard-settings-export" href={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_document.dashboard_id}/export"} class="btn btn-outline btn-sm mt-3">
                <.icon name="hero-arrow-up-tray" class="h-4 w-4" /> Export JSON
              </a>
              <div id="dashboard-deployment-list" phx-update="stream" class="mt-3 space-y-1">
                <p id="dashboard-deployment-empty" class="hidden only:block text-[0.7rem] text-base-content/45">No exports recorded.</p>
                <p :for={{id, deployment} <- @streams.dashboard_deployments} id={id} class="font-mono text-[0.65rem] text-base-content/50">
                  {deployment.environment} · v{deployment.dashboard_version} · {String.slice(deployment.artifact_digest, 0, 10)}
                </p>
              </div>
            </section>
            <section class="border border-base-300 bg-base-200/20 p-4">
              <p class="hud-label">Access posture</p>
              <p class="mt-2 text-sm font-semibold">Mission shared</p>
              <p class="mt-1 text-xs text-base-content/55">
                Mission operators can view this dashboard. Dashboard authors can change its shared
                document.
              </p>
            </section>
            <section class="border border-error/30 bg-error/5 p-4">
              <p class="hud-label text-error">Lifecycle</p>
              <p class="mt-2 text-xs text-base-content/60">
                Archiving removes this dashboard from normal discovery without deleting its version
                history.
              </p>
              <.button
                id="dashboard-settings-archive"
                variant={:ghost}
                size={:sm}
                class="mt-3 text-error"
                phx-click="archive_dashboard"
                data-confirm="Archive this dashboard for every operator on the mission?"
              >
                <.icon name="hero-archive-box" class="h-4 w-4" /> Archive Dashboard
              </.button>
            </section>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp settings_form(%Document{} = document) do
    params = %{
      "name" => document.name,
      "description" => document.description || "",
      "tags" => document.metadata |> metadata_tags() |> Enum.join(", "),
      "defaults_json" => Jason.encode!(document.defaults || %{}, pretty: true)
    }

    to_form(params, as: :settings)
  end

  defp share_form do
    to_form(%{"data_visibility" => "authorized_runtime_data", "expires_in_hours" => "24"},
      as: :share
    )
  end

  defp snapshot_form do
    to_form(%{"data_visibility" => "authorized_runtime_data"}, as: :snapshot)
  end

  defp refresh_management(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    socket
    |> stream(
      :dashboard_shares,
      Management.list_shares(scope.organization_id, mission.mission_id, document.dashboard_id),
      reset: true
    )
    |> stream(
      :dashboard_snapshots,
      Management.list_snapshots(scope.organization_id, mission.mission_id, document.dashboard_id),
      reset: true
    )
    |> stream(
      :dashboard_deployments,
      Management.list_deployments(
        scope.organization_id,
        mission.mission_id,
        document.dashboard_id
      ),
      reset: true
    )
  end

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp settings_document(%Document{} = document, params, name, defaults) do
    metadata =
      document.metadata
      |> ensure_metadata()
      |> Map.delete(:tags)
      |> Map.put("tags", normalize_tags(params["tags"]))

    %Document{
      document
      | name: name,
        description: normalize_text(params["description"]),
        defaults: defaults,
        metadata: metadata
    }
  end

  defp persist_settings(socket, document) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    Cadence.Dashboards.update_document(
      scope.organization_id,
      mission.mission_id,
      document.dashboard_id,
      document,
      expected_version: Document.version(socket.assigns.dashboard_document),
      created_by: current_user_id(scope),
      change_summary: "Updated dashboard settings"
    )
  end

  defp decode_defaults(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, defaults} when is_map(defaults) -> {:ok, defaults}
      {:ok, _other} -> {:error, "Runtime defaults must be a JSON object."}
      {:error, _error} -> {:error, "Runtime defaults contain invalid JSON."}
    end
  end

  defp decode_defaults(_value), do: {:ok, %{}}

  defp required_name(value) do
    case normalize_text(value) do
      nil -> {:error, "Name is required."}
      name -> {:ok, name}
    end
  end

  defp normalize_tags(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_tags(_value), do: []

  defp metadata_tags(metadata) when is_map(metadata) do
    Map.get(metadata, "tags", Map.get(metadata, :tags, [])) |> List.wrap()
  end

  defp metadata_tags(_metadata), do: []
  defp ensure_metadata(metadata) when is_map(metadata), do: metadata
  defp ensure_metadata(_metadata), do: %{}

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_text(_value), do: nil

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
