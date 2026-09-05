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
        application_key="comms"
        surface_id="provider_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

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

  defp profile_status(state) when state in [:active, :ready], do: :ready
  defp profile_status(:degraded), do: :attention
  defp profile_status(_state), do: :blocked

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
end
