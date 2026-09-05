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
         |> assign(:settings_page, settings_page_dto(mission.mission_id, document))
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
    {:noreply, assign(socket, :settings_form, settings_form(params))}
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
       |> assign(
         :settings_page,
         settings_page_dto(socket.assigns.current_mission.mission_id, persisted)
       )
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
      <.vue
        id="ops-dashboard-settings-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_settings"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"dashboard_id" => @active_dashboard_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp settings_page_dto(mission_id, %Document{} = document) do
    dashboard_id = document.dashboard_id

    %{
      id: "dashboard-settings-page",
      header: %{
        eyebrow: "Dashboard / Settings",
        heading: document.name,
        copy: "Durable identity, runtime defaults, discovery metadata, and lifecycle posture.",
        viewer: %{
          id: "dashboard-settings-viewer",
          label: "Back to Viewer",
          href: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}"
        }
      },
      sharing: %{
        id: "dashboard-sharing",
        eyebrow: "Permission-aware sharing",
        heading: "Share this runtime context",
        copy:
          "Links require an authenticated member of this mission. Runtime selectors are captured; credentials and runtime samples are never embedded.",
        list: %{
          id: "dashboard-share-list",
          empty: %{id: "dashboard-share-empty", copy: "No active or revoked links yet."}
        }
      },
      snapshots: %{
        id: "dashboard-snapshots",
        eyebrow: "Read-only snapshots",
        heading: "Freeze definition and context",
        list: %{
          id: "dashboard-snapshot-list",
          empty: %{id: "dashboard-snapshot-empty", copy: "No snapshots yet."}
        }
      },
      portability: %{
        eyebrow: "Governed portability",
        copy:
          "Export includes an integrity digest over binding semantics and records the artifact. Import replaces source identity with the target mission.",
        export: %{
          id: "dashboard-settings-export",
          label: "Export JSON",
          icon: "hero-arrow-up-tray",
          href: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/export"
        },
        deployments: %{
          id: "dashboard-deployment-list",
          empty: %{id: "dashboard-deployment-empty", copy: "No exports recorded."}
        }
      },
      access: %{
        eyebrow: "Access posture",
        heading: "Mission shared",
        copy:
          "Mission operators can view this dashboard. Dashboard authors can change its shared document."
      },
      lifecycle: %{
        eyebrow: "Lifecycle",
        copy:
          "Archiving removes this dashboard from normal discovery without deleting its version history.",
        archive: %{
          id: "dashboard-settings-archive",
          label: "Archive Dashboard",
          icon: "hero-archive-box",
          confirm: "Archive this dashboard for every operator on the mission?"
        }
      }
    }
  end

  defp settings_form(%Document{} = document) do
    params = %{
      "name" => document.name,
      "description" => document.description || "",
      "tags" => document.metadata |> metadata_tags() |> Enum.join(", "),
      "defaults_json" => Jason.encode!(document.defaults || %{}, pretty: true)
    }

    settings_form(params)
  end

  defp settings_form(params) when is_map(params) do
    %{
      id: "dashboard-settings-form",
      fields: %{
        name: %{
          id: "settings_name",
          name: "settings[name]",
          type: "text",
          label: "Name",
          value: form_value(params, "name"),
          required: true
        },
        description: %{
          id: "settings_description",
          name: "settings[description]",
          type: "textarea",
          label: "Description",
          value: form_value(params, "description"),
          required: false
        },
        tags: %{
          id: "settings_tags",
          name: "settings[tags]",
          type: "text",
          label: "Tags",
          value: form_value(params, "tags"),
          required: false,
          placeholder: "power, flight, anomaly-response"
        },
        defaults_json: %{
          id: "settings_defaults_json",
          name: "settings[defaults_json]",
          type: "textarea",
          label: "Runtime defaults (JSON)",
          value: form_value(params, "defaults_json"),
          required: false
        }
      },
      submit: %{id: "dashboard-settings-save", label: "Save Settings"}
    }
  end

  defp share_form do
    %{
      id: "dashboard-share-form",
      fields: %{
        data_visibility: %{
          id: "share_data_visibility",
          name: "share[data_visibility]",
          type: "select",
          label: "Data visibility",
          value: "authorized_runtime_data",
          required: false,
          options: data_visibility_options()
        },
        expires_in_hours: %{
          id: "share_expires_in_hours",
          name: "share[expires_in_hours]",
          type: "number",
          label: "Expires in hours",
          value: "24",
          required: false,
          min: 1,
          placeholder: "Never"
        }
      },
      submit: %{id: "dashboard-share-create", label: "Create authenticated link"}
    }
  end

  defp snapshot_form do
    %{
      id: "dashboard-snapshot-form",
      fields: %{
        data_visibility: %{
          id: "snapshot_data_visibility",
          name: "snapshot[data_visibility]",
          type: "select",
          label: "Data visibility",
          value: "authorized_runtime_data",
          required: false,
          options: data_visibility_options()
        }
      },
      submit: %{id: "dashboard-snapshot-create", label: "Create snapshot"}
    }
  end

  defp refresh_management(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    shares =
      scope.organization_id
      |> Management.list_shares(mission.mission_id, document.dashboard_id)
      |> Enum.map(&dashboard_share_dto(mission.mission_id, &1))

    snapshots =
      scope.organization_id
      |> Management.list_snapshots(mission.mission_id, document.dashboard_id)
      |> Enum.map(&dashboard_snapshot_dto(mission.mission_id, &1))

    deployments =
      scope.organization_id
      |> Management.list_deployments(mission.mission_id, document.dashboard_id)
      |> Enum.map(&dashboard_deployment_dto/1)

    socket
    |> stream(:dashboard_shares, shares, reset: true)
    |> stream(:dashboard_snapshots, snapshots, reset: true)
    |> stream(:dashboard_deployments, deployments, reset: true)
  end

  defp dashboard_share_dto(mission_id, share) do
    share_id = share.dashboard_share_id

    %{
      dashboard_share_id: share_id,
      access_policy: share.access_policy,
      data_visibility: share.data_visibility,
      status: if(is_nil(share.revoked_at), do: "active", else: "revoked"),
      open: %{
        id: "dashboard-share-open-#{share_id}",
        href: ~p"/missions/#{mission_id}/ops/dashboard-shares/#{share_id}"
      },
      revoke:
        if(is_nil(share.revoked_at),
          do: %{
            id: "dashboard-share-revoke-#{share_id}",
            payload: %{"share-id" => share_id}
          },
          else: nil
        )
    }
  end

  defp dashboard_snapshot_dto(mission_id, snapshot) do
    snapshot_id = snapshot.dashboard_snapshot_id

    %{
      dashboard_snapshot_id: snapshot_id,
      dashboard_version: snapshot.dashboard_version,
      data_semantics: snapshot.data_semantics,
      data_visibility: snapshot.data_visibility,
      open: %{
        id: "dashboard-snapshot-open-#{snapshot_id}",
        href: ~p"/missions/#{mission_id}/ops/dashboard-snapshots/#{snapshot_id}"
      }
    }
  end

  defp dashboard_deployment_dto(deployment) do
    %{
      dashboard_deployment_id: deployment.dashboard_deployment_id,
      environment: deployment.environment,
      dashboard_version: deployment.dashboard_version,
      artifact_digest_prefix: String.slice(deployment.artifact_digest, 0, 10)
    }
  end

  defp data_visibility_options do
    [
      %{label: "Authorized runtime data", value: "authorized_runtime_data"},
      %{label: "Definition only", value: "definition_only"}
    ]
  end

  defp form_value(params, field), do: Map.get(params, field) || ""

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
