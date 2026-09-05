defmodule CadenceWeb.CommsProviderShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.Management.Providers, as: ManagementProviders

  alias Cadence.GroundNetworks.{
    DeliveryProfile,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderError,
    ServiceProfile
  }

  alias Phoenix.LiveView.JS

  @impl true
  def mount(%{"provider_id" => provider_id}, _session, socket) do
    socket = assign(socket, :provider_action_opts, provider_action_opts())
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case ManagementProviders.fetch_provider(
           scope.organization_id,
           mission.mission_id,
           provider_id
         ) do
      {:ok, provider} ->
        versions =
          ManagementProviders.list_provider_versions(
            scope.organization_id,
            mission.mission_id,
            provider_id
          )

        {:ok,
         socket
         |> stream_configure(:service_profiles, dom_id: &profile_dom_id("service", &1))
         |> stream_configure(:delivery_profiles, dom_id: &profile_dom_id("delivery", &1))
         |> stream_configure(:provider_versions,
           dom_id: &"provider-version-#{&1.version}"
         )
         |> assign(:page_title, provider.display_name)
         |> assign(:nav_item, :comms_providers)
         |> assign(:provider, provider)
         |> assign_provider_binding(provider)
         |> assign(:provider_action, nil)
         |> assign_profile_counts(provider)
         |> stream_provider_data(provider, versions)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Ground network provider not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/providers")}
    end
  end

  @impl true
  def handle_event("validate-provider", _params, %{assigns: %{provider_action: nil}} = socket) do
    %{current_scope: scope, current_mission: mission, provider: provider} = socket.assigns
    opts = socket.assigns.provider_action_opts

    {:noreply,
     socket
     |> assign(:provider_action, :validate)
     |> start_async(:validate_provider, fn ->
       ControlProviders.validate_current(scope, mission.mission_id, provider.provider_id, opts)
     end)}
  end

  def handle_event("validate-provider", _params, socket), do: {:noreply, socket}

  def handle_event("sync-provider", _params, %{assigns: %{provider_action: nil}} = socket) do
    %{current_scope: scope, current_mission: mission, provider: provider} = socket.assigns
    opts = socket.assigns.provider_action_opts

    {:noreply,
     socket
     |> assign(:provider_action, :sync)
     |> start_async(:sync_provider, fn ->
       ControlProviders.sync_current(scope, mission.mission_id, provider.provider_id, opts)
     end)}
  end

  def handle_event("sync-provider", _params, socket), do: {:noreply, socket}

  def handle_event("archive-provider", _params, socket) do
    %{current_scope: scope, current_mission: mission, provider: provider} = socket.assigns

    case ManagementProviders.archive_provider(scope, mission.mission_id, provider.provider_id) do
      {:ok, _archived} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ground network provider archived.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/providers")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  @impl true
  def handle_async(:validate_provider, {:ok, {:ok, _provider}}, socket) do
    {:noreply,
     socket
     |> assign(:provider_action, nil)
     |> refresh_provider()
     |> put_flash(:info, "Provider control plane validated.")}
  end

  def handle_async(:sync_provider, {:ok, {:ok, _provider}}, socket) do
    {:noreply,
     socket
     |> assign(:provider_action, nil)
     |> refresh_provider()
     |> put_flash(:info, "Provider inventory and profiles synchronized.")}
  end

  def handle_async(_action, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:provider_action, nil)
     |> refresh_provider()
     |> put_flash(:error, action_error(reason))}
  end

  def handle_async(_action, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:provider_action, nil)
     |> refresh_provider()
     |> put_flash(:error, "Provider operation stopped unexpectedly: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-provider-show-component"
        v-component="FederatedFullPageSurface"
        navigation={navigation_dto(@current_mission, @provider)}
        provider={provider_dto(@provider, @service_profile_count, @delivery_profile_count)}
        actions={actions_dto(@provider_action)}
        profiles={profiles_dto(@service_profiles_empty?, @delivery_profiles_empty?)}
        details={details_dto(@provider)}
        diagnostics={diagnostics_dto(@provider)}
        service_profiles={@streams.service_profiles}
        delivery_profiles={@streams.delivery_profiles}
        provider_versions={@streams.provider_versions}
        v-on:validate-provider={JS.push("validate-provider")}
        v-on:sync-provider={JS.push("sync-provider")}
        v-on:archive-provider={JS.push("archive-provider")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp navigation_dto(mission, provider) do
    %{
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{
          label: "Providers",
          href: ~p"/missions/#{mission.mission_id}/comms/providers"
        },
        %{label: provider.display_name, href: nil}
      ]
    }
  end

  defp provider_dto(provider, service_profile_count, delivery_profile_count) do
    %{
      page_id: "comms-provider-show-page",
      display_name: provider.display_name,
      provider_id: provider.provider_id,
      simulated_badge: %{id: "simulated-provider-badge", label: "Simulated"},
      version: "v#{provider.version}",
      summary_tiles: [
        summary_tile(
          "provider-control-plane-health",
          "Control Plane",
          control_plane_label(provider)
        ),
        summary_tile("provider-last-sync", "Last Sync", timestamp_label(provider.last_synced_at)),
        summary_tile(
          "provider-service-profile-count",
          "Service Profiles",
          service_profile_count
        ),
        summary_tile(
          "provider-delivery-profile-count",
          "Delivery Profiles",
          delivery_profile_count
        )
      ]
    }
  end

  defp summary_tile(id, label, value), do: %{id: id, label: label, value: value}

  defp actions_dto(provider_action) do
    disabled? = not is_nil(provider_action)

    %{
      validate: %{
        id: "validate-provider-button",
        label: if(provider_action == :validate, do: "Validating…", else: "Validate"),
        disabled: disabled?
      },
      sync: %{
        id: "sync-provider-button",
        label: if(provider_action == :sync, do: "Syncing…", else: "Sync Inventory"),
        disabled: disabled?
      },
      archive: %{
        id: "archive-provider-button",
        label: "Archive",
        confirm: "Archive this ground network provider?",
        disabled: disabled?
      }
    }
  end

  defp profiles_dto(service_profiles_empty?, delivery_profiles_empty?) do
    %{
      service: %{
        id: "provider-service-profiles",
        heading: "Service Profiles",
        subtitle: "Provider-owned service definitions available to contact scheduling.",
        empty: service_profiles_empty?,
        empty_copy: "Sync provider inventory to discover service profiles.",
        table_id: "service-profiles-table",
        table_body_id: "service-profiles-table-body",
        columns: ["Service", "Kind", "Direction", "Data Families", "State"]
      },
      delivery: %{
        id: "provider-delivery-profiles",
        heading: "Delivery Profiles",
        subtitle:
          "Provider delivery options; Cadence transports are resolved from these profiles later.",
        empty: delivery_profiles_empty?,
        empty_copy: "Sync provider inventory to discover delivery profiles.",
        table_id: "delivery-profiles-table",
        table_body_id: "delivery-profiles-table-body",
        columns: ["Delivery", "Kind", "Direction", "Provider State"]
      }
    }
  end

  defp details_dto(provider) do
    %{
      configuration: %{
        id: "provider-configuration",
        title: "Configuration",
        rows: [
          detail_dto("Provider type", humanize(provider.provider_type)),
          detail_dto(
            "Provider Account",
            binding_label(provider.provider_account_id, provider.provider_account_version),
            true
          ),
          detail_dto(
            "Mission Grant",
            binding_label(
              provider.provider_account_grant_id,
              provider.provider_account_grant_version
            ),
            true
          ),
          detail_dto("Validated", timestamp_label(provider.last_validated_at))
        ]
      },
      delivery_policy: %{
        id: "provider-delivery-policy",
        title: "Delivery Change Policy",
        rows: [
          detail_dto(
            "Mode",
            humanize(Map.get(provider.delivery_policy_document, "mode", "approval_required"))
          ),
          detail_dto(
            "Deadline behavior",
            humanize(
              Map.get(
                provider.delivery_policy_document,
                "deadline_behavior",
                "retain_last_accepted"
              )
            )
          ),
          detail_dto(
            "Permitted resources",
            resource_summary(provider.permitted_resource_refs)
          )
        ]
      },
      capabilities: capabilities_dto(provider),
      version_history: %{
        id: "provider-version-history",
        title: "Version History",
        stream_id: "provider-versions"
      }
    }
  end

  defp capabilities_dto(provider) do
    items =
      Enum.map(capability_items(provider), fn {capability, supported?} ->
        %{
          label: humanize(capability),
          status: %{
            tone: if(supported?, do: "ready", else: "blocked"),
            label: if(supported?, do: "Supported", else: "Unavailable")
          }
        }
      end)

    %{
      id: "provider-capabilities",
      title: "Capabilities",
      empty: items == [],
      empty_copy: "Validate the provider to load its declared capabilities.",
      items: items
    }
  end

  defp diagnostics_dto(provider) do
    %{
      id: "provider-admin-diagnostics",
      label: "Admin Diagnostics",
      json_id: "provider-admin-diagnostics-json",
      rows: [
        detail_dto("Account ID", provider.provider_account_id || "Legacy setup", true),
        detail_dto(
          "Account version",
          version_label(provider.provider_account_version),
          true
        ),
        detail_dto("Grant ID", provider.provider_account_grant_id || "Not granted", true),
        detail_dto(
          "Grant version",
          version_label(provider.provider_account_grant_version),
          true
        )
      ],
      json: diagnostics_json(provider)
    }
  end

  defp detail_dto(label, value, mono? \\ false),
    do: %{label: label, value: value, mono: mono?}

  defp refresh_provider(socket) do
    %{current_scope: scope, current_mission: mission, provider: current} = socket.assigns

    case ManagementProviders.fetch_provider(
           scope.organization_id,
           mission.mission_id,
           current.provider_id
         ) do
      {:ok, provider} ->
        versions =
          ManagementProviders.list_provider_versions(
            scope.organization_id,
            mission.mission_id,
            provider.provider_id
          )

        socket
        |> assign(:provider, provider)
        |> assign_provider_binding(provider)
        |> assign(:page_title, provider.display_name)
        |> assign_profile_counts(provider)
        |> stream_provider_data(provider, versions, reset: true)

      {:error, _reason} ->
        socket
    end
  end

  defp stream_provider_data(socket, provider, versions, opts \\ []) do
    reset? = Keyword.get(opts, :reset, false)

    socket
    |> stream(
      :service_profiles,
      provider |> profile_items("service_profiles") |> Enum.map(&service_profile_dto/1),
      reset: reset?
    )
    |> stream(
      :delivery_profiles,
      provider |> profile_items("delivery_profiles") |> Enum.map(&delivery_profile_dto/1),
      reset: reset?
    )
    |> stream(:provider_versions, Enum.map(versions, &provider_version_dto/1), reset: reset?)
  end

  defp assign_profile_counts(socket, provider) do
    service_profiles = profile_items(provider, "service_profiles")
    delivery_profiles = profile_items(provider, "delivery_profiles")

    socket
    |> assign(:service_profile_count, length(service_profiles))
    |> assign(:service_profiles_empty?, service_profiles == [])
    |> assign(:delivery_profile_count, length(delivery_profiles))
    |> assign(:delivery_profiles_empty?, delivery_profiles == [])
  end

  defp profile_items(provider, key) do
    case get_in(provider.inventory_sync_document, [key, "items"]) do
      items when is_list(items) -> normalize_profiles(key, items)
      _other -> []
    end
  end

  defp profile_dom_id(kind, profile), do: "#{kind}-profile-#{profile.id}"

  defp service_profile_dto(profile) do
    %{
      id: profile.id,
      display_name: profile.display_name,
      service_kind: profile.service_kind,
      direction: Atom.to_string(profile.direction),
      data_families: Enum.join(profile.data_families, ", "),
      status: %{
        tone: profile.state |> profile_status() |> Atom.to_string(),
        label: humanize(profile.state)
      }
    }
  end

  defp delivery_profile_dto(profile) do
    %{
      id: profile.id,
      display_name: profile.display_name,
      operator_summary: profile.operator_summary,
      delivery_kind: profile.delivery_kind,
      direction: Atom.to_string(profile.direction),
      status: %{
        tone: profile.state |> profile_status() |> Atom.to_string(),
        label: humanize(profile.state)
      }
    }
  end

  defp provider_version_dto(version) do
    %{
      version: version.version,
      lifecycle_state: version.lifecycle_state |> Atom.to_string() |> String.upcase()
    }
  end

  defp provider_action_opts do
    Application.get_env(:cadence_web, :ground_network_provider_live_opts, [])
  end

  defp control_plane_label(provider) do
    case get_in(provider.metadata, ["control_plane", "status"]) do
      "healthy" -> "Healthy"
      "failed" -> "Failed"
      _other -> "Not validated"
    end
  end

  defp timestamp_label(nil), do: "Never"

  defp timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")

  defp profile_status(state) when state in [:active, :ready], do: :ready
  defp profile_status(:degraded), do: :attention
  defp profile_status(_state), do: :blocked

  defp capability_items(provider) do
    provider.capabilities_document
    |> Map.get("operations", %{})
    |> Enum.sort_by(fn {name, _supported?} -> name end)
  end

  defp diagnostics_json(provider) do
    Jason.encode!(
      %{
        "control_plane" => provider.metadata["control_plane"],
        "sync" => provider.metadata["sync"],
        "capabilities" => provider.capabilities_document,
        "inventory_summary" => inventory_counts(provider.inventory_sync_document),
        "service_profiles" =>
          provider |> profile_items("service_profiles") |> Enum.map(& &1.evidence),
        "delivery_profiles" =>
          provider |> profile_items("delivery_profiles") |> Enum.map(& &1.evidence)
      },
      pretty: true
    )
  end

  defp inventory_counts(document) do
    for key <- ["spacecraft", "ground_stations", "service_profiles", "delivery_profiles"],
        into: %{} do
      {key, Map.take(Map.get(document, key, %{}), ["total_count", "cached_count", "truncated"])}
    end
  end

  defp humanize(value) when is_atom(value), do: value |> Atom.to_string() |> humanize()

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp action_error(%ProviderError{} = error), do: error.detail
  defp action_error(reason), do: "Provider operation failed: #{inspect(reason)}"

  defp assign_provider_binding(socket, %{provider_account_id: nil}) do
    socket
    |> assign(:provider_account_version, nil)
    |> assign(:provider_account_grant, nil)
  end

  defp assign_provider_binding(socket, provider) do
    {:ok, account_version} =
      ProviderAccounts.fetch_version(
        provider.organization_id,
        provider.provider_account_id,
        provider.provider_account_version
      )

    {:ok, grant} =
      ProviderAccountGrants.fetch_version(
        provider.organization_id,
        provider.provider_account_grant_id,
        provider.mission_id,
        provider.provider_account_grant_version
      )

    socket
    |> assign(:provider_account_version, account_version)
    |> assign(:provider_account_grant, grant)
  end

  defp normalize_profiles("service_profiles", items) do
    Enum.flat_map(items, fn item ->
      case ServiceProfile.from_external(item) do
        {:ok, profile} -> [profile]
        {:error, _reason} -> []
      end
    end)
  end

  defp normalize_profiles("delivery_profiles", items) do
    Enum.flat_map(items, fn item ->
      case DeliveryProfile.from_external(item) do
        {:ok, profile} -> [profile]
        {:error, _reason} -> []
      end
    end)
  end

  defp binding_label(nil, _version), do: "Legacy setup"
  defp binding_label(id, version), do: "#{id} · v#{version}"
  defp version_label(nil), do: "Not available"
  defp version_label(version), do: "v#{version}"
  defp resource_summary([]), do: "Inherited from grant"
  defp resource_summary(resources), do: Enum.join(resources, ", ")
end
