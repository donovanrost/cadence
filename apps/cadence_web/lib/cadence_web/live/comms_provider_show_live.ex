defmodule CadenceWeb.CommsProviderShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.ProviderError

  @impl true
  def mount(%{"provider_id" => provider_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case GroundNetworks.fetch_provider(scope.organization_id, mission.mission_id, provider_id) do
      {:ok, provider} ->
        versions =
          GroundNetworks.list_provider_versions(
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
    opts = provider_action_opts()

    {:noreply,
     socket
     |> assign(:provider_action, :validate)
     |> start_async(:validate_provider, fn ->
       GroundNetworks.validate_provider(
         scope.organization_id,
         mission.mission_id,
         provider.provider_id,
         opts
       )
     end)}
  end

  def handle_event("validate-provider", _params, socket), do: {:noreply, socket}

  def handle_event("sync-provider", _params, %{assigns: %{provider_action: nil}} = socket) do
    %{current_scope: scope, current_mission: mission, provider: provider} = socket.assigns
    opts = provider_action_opts()

    {:noreply,
     socket
     |> assign(:provider_action, :sync)
     |> start_async(:sync_provider, fn ->
       GroundNetworks.sync_provider(
         scope.organization_id,
         mission.mission_id,
         provider.provider_id,
         opts
       )
     end)}
  end

  def handle_event("sync-provider", _params, socket), do: {:noreply, socket}

  def handle_event("archive-provider", _params, socket) do
    %{current_scope: scope, current_mission: mission, provider: provider} = socket.assigns

    case GroundNetworks.archive_provider(
           scope.organization_id,
           mission.mission_id,
           provider.provider_id
         ) do
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
    <div id="comms-provider-show-page" class="space-y-6">
      <.page_header
        title={@provider.display_name}
        subtitle={@provider.provider_id}
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Providers", ~p"/missions/#{@current_mission.mission_id}/comms/providers"},
          {@provider.display_name, nil}
        ]}
      >
        <:title_suffix>
          <span
            id="simulated-provider-badge"
            class="inline-flex rounded-full bg-info/20 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide text-info"
          >
            Simulated
          </span>
          <span class="ml-2 font-mono text-xs text-base-content/60">v{@provider.version}</span>
        </:title_suffix>
        <:actions>
          <.button
            id="validate-provider-button"
            variant={:secondary}
            phx-click="validate-provider"
            disabled={!is_nil(@provider_action)}
          >
            <.icon name="hero-shield-check" class="h-4 w-4" />
            {if(@provider_action == :validate, do: "Validating…", else: "Validate")}
          </.button>
          <.button
            id="sync-provider-button"
            phx-click="sync-provider"
            disabled={!is_nil(@provider_action)}
          >
            <.icon name="hero-arrow-path" class="h-4 w-4" />
            {if(@provider_action == :sync, do: "Syncing…", else: "Sync Inventory")}
          </.button>
          <.button
            id="archive-provider-button"
            variant={:danger}
            phx-click="archive-provider"
            data-confirm="Archive this ground network provider?"
            disabled={!is_nil(@provider_action)}
          >
            Archive
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-3 md:grid-cols-4">
        <.stat_tile
          id="provider-control-plane-health"
          label="Control Plane"
          value={control_plane_label(@provider)}
        />
        <.stat_tile id="provider-last-sync" label="Last Sync" value={timestamp_label(@provider.last_synced_at)} />
        <.stat_tile id="provider-service-profile-count" label="Service Profiles" value={@service_profile_count} />
        <.stat_tile id="provider-delivery-profile-count" label="Delivery Profiles" value={@delivery_profile_count} />
      </div>

      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-4">
          <.card
            id="provider-service-profiles"
            heading="Service Profiles"
            subtitle="Provider-owned service definitions available to contact scheduling."
            padding={:none}
          >
            <div :if={@service_profiles_empty?} class="p-6 text-sm text-base-content/60">
              Sync provider inventory to discover service profiles.
            </div>
            <.table :if={!@service_profiles_empty?} id="service-profiles-table" rows={@streams.service_profiles}>
              <:col :let={profile} label="Service">{profile["display_name"]}</:col>
              <:col :let={profile} label="Kind" mono>{profile["service_kind"]}</:col>
              <:col :let={profile} label="Direction" mono>{profile["direction"]}</:col>
              <:col :let={profile} label="Data Families" mono>
                {Enum.join(profile["data_families"] || [], ", ")}
              </:col>
              <:col :let={profile} label="State">
                <.status_badge
                  status={profile_status(profile["state"])}
                  label={profile["state"]}
                />
              </:col>
            </.table>
          </.card>

          <.card
            id="provider-delivery-profiles"
            heading="Delivery Profiles"
            subtitle="Provider delivery options; Cadence transports are resolved from these profiles later."
            padding={:none}
          >
            <div :if={@delivery_profiles_empty?} class="p-6 text-sm text-base-content/60">
              Sync provider inventory to discover delivery profiles.
            </div>
            <.table :if={!@delivery_profiles_empty?} id="delivery-profiles-table" rows={@streams.delivery_profiles}>
              <:col :let={profile} label="Delivery">
                <div>{profile["display_name"]}</div>
                <div class="mt-1 text-xs text-base-content/60">
                  {profile["operator_summary"]}
                </div>
              </:col>
              <:col :let={profile} label="Kind" mono>{profile["delivery_kind"]}</:col>
              <:col :let={profile} label="Direction" mono>{profile["direction"]}</:col>
              <:col :let={profile} label="Provider State">
                <.status_badge
                  status={profile_status(profile["state"])}
                  label={profile["state"]}
                />
              </:col>
            </.table>
          </.card>
        </div>

        <aside class="space-y-4">
          <.card id="provider-configuration" title="Configuration">
            <div class="mt-3 divide-y divide-base-300">
              <.detail_row label="Provider type" value={humanize(@provider.provider_type)} />
              <.detail_row label="Environment" value={@provider.environment_ref} mono />
              <.detail_row label="Credential ref" value={@provider.credential_ref} mono />
              <.detail_row label="Validated" value={timestamp_label(@provider.last_validated_at)} />
            </div>
          </.card>

          <.card id="provider-capabilities" title="Capabilities">
            <div class="mt-3 space-y-2">
              <div
                :if={capability_items(@provider) == []}
                class="text-sm text-base-content/60"
              >
                Validate the provider to load its declared capabilities.
              </div>
              <div
                :for={{capability, supported?} <- capability_items(@provider)}
                class="flex items-center justify-between gap-3 text-sm"
              >
                <span>{humanize(capability)}</span>
                <.status_badge
                  status={if(supported?, do: :ready, else: :blocked)}
                  label={if(supported?, do: "Supported", else: "Unavailable")}
                />
              </div>
            </div>
          </.card>

          <.card id="provider-version-history" title="Version History">
            <div id="provider-versions" phx-update="stream" class="mt-3 divide-y divide-base-300">
              <div :for={{dom_id, version} <- @streams.provider_versions} id={dom_id}>
                <.detail_row
                  label={"v#{version.version}"}
                  value={version.lifecycle_state |> Atom.to_string() |> String.upcase()}
                />
              </div>
            </div>
          </.card>
        </aside>
      </div>

      <details
        id="provider-admin-diagnostics"
        class="rounded border border-base-300 bg-base-200/60 p-4 text-sm"
      >
        <summary class="cursor-pointer hud-label hover:text-primary">Admin Diagnostics</summary>
        <div class="mt-4 grid gap-4 lg:grid-cols-2">
          <div class="divide-y divide-base-300">
            <.detail_row label="API base URL" value={@provider.base_url} mono />
            <.detail_row label="Client adapter" value={Atom.to_string(@provider.client_key)} mono />
            <.detail_row label="Credential reference" value={@provider.credential_ref} mono />
          </div>
          <pre id="provider-admin-diagnostics-json" class="max-h-80 overflow-auto border border-base-300 bg-base-100/50 p-3 font-mono text-xs text-base-content/70">{diagnostics_json(@provider)}</pre>
        </div>
      </details>
    </div>
    """
  end

  defp refresh_provider(socket) do
    %{current_scope: scope, current_mission: mission, provider: current} = socket.assigns

    case GroundNetworks.fetch_provider(
           scope.organization_id,
           mission.mission_id,
           current.provider_id
         ) do
      {:ok, provider} ->
        versions =
          GroundNetworks.list_provider_versions(
            scope.organization_id,
            mission.mission_id,
            provider.provider_id
          )

        socket
        |> assign(:provider, provider)
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
    |> stream(:service_profiles, profile_items(provider, "service_profiles"), reset: reset?)
    |> stream(:delivery_profiles, profile_items(provider, "delivery_profiles"), reset: reset?)
    |> stream(:provider_versions, versions, reset: reset?)
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
      items when is_list(items) -> items
      _other -> []
    end
  end

  defp profile_dom_id(kind, profile), do: "#{kind}-profile-#{profile["id"]}"

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

  defp profile_status(state) when state in ["active", "ready"], do: :ready
  defp profile_status("degraded"), do: :attention
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
        "service_profiles" => profile_items(provider, "service_profiles"),
        "delivery_profiles" => profile_items(provider, "delivery_profiles")
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
end
