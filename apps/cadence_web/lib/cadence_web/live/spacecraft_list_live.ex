defmodule CadenceWeb.SpacecraftListLive do
  @moduledoc """
  Exception-first spacecraft management page.

  Canonical URL-driven list pattern: `handle_params/3` parses
  `?q=&sort=&dir=&page=&filter=` via `CadenceWeb.ListParams`, fetches one
  page from `Cadence.list_spacecraft_page/3`, and toolbar events translate
  into `push_patch` — so list state is shareable and back-button-safe.
  """

  use CadenceWeb, :live_view

  import CadenceWeb.SpacecraftListComponents

  alias CadenceWeb.ListParams

  @page_size 50
  @profile_preview_limit 5
  @sortable ~w(display_name scid)

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    profiles = Cadence.list_spacecraft_types(organization_id, mission.mission_id)
    latest_versions = Map.new(profiles, &{&1.spacecraft_type_id, &1.version})
    summary = Cadence.spacecraft_fleet_summary(organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:profiles_by_id, Map.new(profiles, &{&1.spacecraft_type_id, &1}))
     |> assign(:latest_versions, latest_versions)
     |> assign(:summary, summary)
     |> assign(:drift_count, drift_count(summary, latest_versions))
     |> assign(:version_counts_by_profile, version_counts_by_profile(summary))
     |> assign(:fleet_empty?, summary.total == 0)
     |> assign(:profile_count, length(profiles))
     |> assign(:profiles_empty?, profiles == [])
     |> assign(:profiles_truncated?, length(profiles) > @profile_preview_limit)
     |> stream(:spacecraft_profiles, Enum.take(profiles, @profile_preview_limit),
       dom_id: &"spacecraft-profile-preview-#{&1.spacecraft_type_id}"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    list = ListParams.parse(params, sortable: @sortable, default_sort: "display_name")
    filter = parse_filter(params["filter"])
    {list, page} = fetch_roster(organization_id, mission.mission_id, list, filter, socket)

    {:noreply,
     socket
     |> assign(:list, list)
     |> assign(:filter, filter)
     |> assign(:roster, %{page | items: []})
     |> stream(:spacecraft, page.items,
       reset: true,
       dom_id: &"spacecraft-#{&1.spacecraft_id}"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    list = %{socket.assigns.list | q: q, page: 1}
    {:noreply, patch_roster(socket, list)}
  end

  @impl true
  def handle_event("sort", %{"sort" => key}, socket) when key in @sortable do
    {:noreply, patch_roster(socket, ListParams.toggle_sort(socket.assigns.list, key))}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    list = %{socket.assigns.list | page: ListParams.parse(%{"page" => page}, sortable: []).page}
    {:noreply, patch_roster(socket, list)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-management-page" class="space-y-6">
      <.page_header
        title="Spacecraft"
        subtitle="Manage mission spacecraft identities and reusable spacecraft profiles."
        back_label={@current_mission.display_name}
        back_navigate={~p"/missions/#{@current_mission.mission_id}"}
      />

      <.summary_tiles
        mission_id={@current_mission.mission_id}
        summary={@summary}
        drift_count={@drift_count}
        list={@list}
        filter={@filter}
      />

      <.roster_card
        mission_id={@current_mission.mission_id}
        rows={@streams.spacecraft}
        list={@list}
        filter={@filter}
        roster={@roster}
        fleet_empty?={@fleet_empty?}
        summary={@summary}
        profiles_by_id={@profiles_by_id}
        latest_versions={@latest_versions}
      />

      <.profiles_card
        mission_id={@current_mission.mission_id}
        rows={@streams.spacecraft_profiles}
        list={@list}
        profiles_empty?={@profiles_empty?}
        profiles_truncated?={@profiles_truncated?}
        profile_count={@profile_count}
        drift_count={@drift_count}
        version_counts_by_profile={@version_counts_by_profile}
        latest_versions={@latest_versions}
      />
    </div>
    """
  end

  defp fetch_roster(organization_id, mission_id, list, filter, socket) do
    page =
      Cadence.list_spacecraft_page(organization_id, mission_id,
        search: list.q,
        sort: sort_tuple(list),
        filter: store_filter(filter, socket.assigns.latest_versions),
        page: list.page,
        page_size: @page_size
      )

    last_page = max(ceil(page.total_count / @page_size), 1)

    if list.page > last_page and page.total_count > 0 do
      # A ?page= past the end (stale link, shrunken filter) clamps to the
      # last real page instead of rendering an empty table.
      fetch_roster(organization_id, mission_id, %{list | page: last_page}, filter, socket)
    else
      {list, page}
    end
  end

  defp patch_roster(socket, list) do
    mission_id = socket.assigns.current_mission.mission_id
    query = ListParams.to_query(list, filter: serialize_filter(socket.assigns.filter))
    push_patch(socket, to: ~p"/missions/#{mission_id}/spacecraft?#{query}")
  end

  defp parse_filter("missing_profile"), do: :missing_profile
  defp parse_filter("missing_scid"), do: :missing_scid
  defp parse_filter("drift"), do: :drift
  defp parse_filter("profile:" <> spacecraft_type_id), do: {:profile, spacecraft_type_id}
  defp parse_filter(_other), do: nil

  defp serialize_filter(:missing_profile), do: "missing_profile"
  defp serialize_filter(:missing_scid), do: "missing_scid"
  defp serialize_filter(:drift), do: "drift"
  defp serialize_filter({:profile, spacecraft_type_id}), do: "profile:" <> spacecraft_type_id
  defp serialize_filter(nil), do: nil

  defp store_filter(:drift, latest_versions), do: {:stale_versions, latest_versions}
  defp store_filter(filter, _latest_versions), do: filter

  defp sort_tuple(%ListParams{sort: "display_name", dir: dir}), do: {:display_name, dir}
  defp sort_tuple(%ListParams{sort: "scid", dir: dir}), do: {:scid, dir}

  defp drift_count(summary, latest_versions) do
    summary.profile_version_counts
    |> Enum.filter(fn entry ->
      case Map.get(latest_versions, entry.spacecraft_type_id) do
        nil ->
          false

        latest ->
          is_integer(entry.spacecraft_type_version) and entry.spacecraft_type_version < latest
      end
    end)
    |> Enum.map(& &1.count)
    |> Enum.sum()
  end

  defp version_counts_by_profile(summary) do
    Enum.group_by(summary.profile_version_counts, & &1.spacecraft_type_id)
  end
end
