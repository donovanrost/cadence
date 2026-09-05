defmodule CadenceWeb.SpacecraftListLive do
  @moduledoc """
  Exception-first spacecraft management page.

  Canonical URL-driven list pattern: `handle_params/3` parses
  `?q=&sort=&dir=&page=&filter=` via `CadenceWeb.ListParams`, fetches one
  page from `Cadence.SpacecraftStore.list_spacecraft_page/3`, and toolbar events translate
  into `push_patch` — so list state is shareable and back-button-safe.
  """

  use CadenceWeb, :live_view

  alias CadenceWeb.ListParams

  @page_size 50
  @profile_preview_limit 5
  @sortable ~w(display_name scid)

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    profiles =
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission.mission_id)

    latest_versions = Map.new(profiles, &{&1.spacecraft_type_id, &1.version})
    summary = Cadence.SpacecraftStore.fleet_summary(organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:profiles, profiles)
     |> assign(:profiles_by_id, Map.new(profiles, &{&1.spacecraft_type_id, &1}))
     |> assign(:latest_versions, latest_versions)
     |> assign(:summary, summary)
     |> assign(:drift_count, drift_count(summary, latest_versions))
     |> assign(:version_counts_by_profile, version_counts_by_profile(summary))
     |> assign(:presentation, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    list = ListParams.parse(params, sortable: @sortable, default_sort: "display_name")
    filter = parse_filter(params["filter"])
    {list, page} = fetch_roster(organization_id, mission.mission_id, list, filter, socket)
    presentation = page_presentation_dto(mission, list, filter, page, socket)

    {:noreply,
     socket
     |> assign(:list, list)
     |> assign(:filter, filter)
     |> assign(:presentation, presentation)}
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-list-component"
        v-component="FederatedFullPageSurface"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp page_presentation_dto(mission, list, filter, page, socket) do
    mission_id = mission.mission_id

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "spacecraft-management-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(),
      "breadcrumbs" => breadcrumbs_presentation(mission),
      "summary_tiles" =>
        summary_tiles_dto(
          mission_id,
          list,
          filter,
          socket.assigns.summary,
          socket.assigns.drift_count
        ),
      "roster" =>
        roster_dto(
          mission_id,
          list,
          page,
          socket.assigns.summary,
          socket.assigns.profiles_by_id,
          socket.assigns.latest_versions
        ),
      "profiles" =>
        profiles_dto(
          mission_id,
          list,
          socket.assigns.profiles,
          socket.assigns.drift_count,
          socket.assigns.version_counts_by_profile,
          socket.assigns.latest_versions
        )
    }
  end

  defp header_presentation do
    %{
      "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
      "body" => %{"attrs" => %{}},
      "content" => %{"attrs" => %{}},
      "title" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
          }),
        "text" => "Spacecraft"
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" => "Manage mission spacecraft identities and reusable spacecraft profiles."
      }
    }
  end

  defp breadcrumbs_presentation(mission) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "aria-label" => "Breadcrumb",
          "class" =>
            "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        }),
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{
            "attrs" =>
              navigate_attrs(~p"/missions/#{mission.mission_id}", %{
                "class" => "hover:text-primary transition-colors"
              }),
            "text" => mission.display_name
          },
          "current" => nil
        },
        %{
          "key" => "spacecraft",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Spacecraft"
          }
        }
      ]
    }
  end

  defp breadcrumb_separator do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" => "text-base-content/20",
          "aria-hidden" => "true"
        }),
      "text" => "/"
    }
  end

  defp navigate_attrs(href, extra_attrs) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
    |> Map.merge(extra_attrs)
    |> presentation_attrs()
  end

  defp fetch_roster(organization_id, mission_id, list, filter, socket) do
    page =
      Cadence.SpacecraftStore.list_spacecraft_page(organization_id, mission_id,
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

  defp summary_tiles_dto(mission_id, list, filter, summary, drift_count) do
    [
      summary_tile_dto(
        "spacecraft-tile-all",
        "Vehicles",
        summary.total,
        filter_path(mission_id, list, nil),
        is_nil(filter),
        false
      ),
      summary_tile_dto(
        "spacecraft-tile-missing-scid",
        "Missing SCID",
        summary.missing_scid,
        filter_path(mission_id, list, "missing_scid"),
        filter == :missing_scid,
        summary.missing_scid > 0
      ),
      summary_tile_dto(
        "spacecraft-tile-missing-profile",
        "Missing profile",
        summary.missing_profile,
        filter_path(mission_id, list, "missing_profile"),
        filter == :missing_profile,
        summary.missing_profile > 0
      ),
      summary_tile_dto(
        "spacecraft-tile-drift",
        "Profile drift",
        drift_count,
        filter_path(mission_id, list, "drift"),
        filter == :drift,
        drift_count > 0
      )
    ]
  end

  defp summary_tile_dto(id, label, value, href, active, warning) do
    %{id: id, label: label, value: value, href: href, active: active, warning: warning}
  end

  defp roster_dto(mission_id, list, page, summary, profiles_by_id, latest_versions) do
    last_page = max(ceil(page.total_count / page.page_size), 1)

    %{
      fleet_empty: summary.total == 0,
      subtitle: "#{summary.total} total · #{summary.missing_profile} missing profile",
      new_spacecraft_href: ~p"/missions/#{mission_id}/spacecraft/new",
      search: list.q || "",
      sort_by: list.sort,
      sort_dir: Atom.to_string(list.dir),
      filtered_empty: page.total_count == 0,
      page: page.page,
      page_size: page.page_size,
      total_count: page.total_count,
      pagination_visible: page.total_count > page.page_size,
      range_label: range_label(page),
      previous_page: page.page - 1,
      next_page: page.page + 1,
      previous_disabled: page.page <= 1,
      next_disabled: page.page >= last_page,
      rows:
        Enum.map(
          page.items,
          &spacecraft_row_dto(&1, mission_id, profiles_by_id, latest_versions)
        )
    }
  end

  defp spacecraft_row_dto(spacecraft, mission_id, profiles_by_id, latest_versions) do
    status = setup_status(spacecraft, latest_versions)

    %{
      id: "spacecraft-#{spacecraft.spacecraft_id}",
      actions_id: "#{spacecraft.spacecraft_id}-actions",
      display_name: spacecraft.display_name,
      scid_label: if(spacecraft.scid, do: to_string(spacecraft.scid), else: "Not set"),
      scid_missing: is_nil(spacecraft.scid),
      profile_label: profile_label(spacecraft, profiles_by_id),
      status: Atom.to_string(status),
      status_label: setup_status_label(spacecraft, latest_versions),
      href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}",
      identity_href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
    }
  end

  defp profiles_dto(
         mission_id,
         list,
         profiles,
         drift_count,
         version_counts_by_profile,
         latest_versions
       ) do
    %{
      empty: profiles == [],
      truncated: length(profiles) > @profile_preview_limit,
      subtitle: "#{length(profiles)} total · #{drift_count} drift warning",
      new_profile_href: ~p"/missions/#{mission_id}/spacecraft/profiles/new",
      all_profiles_href: ~p"/missions/#{mission_id}/spacecraft/profiles",
      rows:
        profiles
        |> Enum.take(@profile_preview_limit)
        |> Enum.map(
          &profile_row_dto(
            &1,
            mission_id,
            list,
            Map.get(version_counts_by_profile, &1.spacecraft_type_id, []),
            Map.get(latest_versions, &1.spacecraft_type_id)
          )
        )
    }
  end

  defp profile_row_dto(profile, mission_id, list, version_counts, latest_version) do
    status = profile_status(profile)

    %{
      id: "spacecraft-profile-preview-#{profile.spacecraft_type_id}",
      display_name: profile.display_name,
      href: ~p"/missions/#{mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}",
      fleet_entries:
        profile_fleet_entries(profile, mission_id, list, version_counts, latest_version),
      protocols: "#{profile.downlink_protocol} / #{profile.uplink_protocol}",
      applications: applications_summary(profile.applications),
      status: Atom.to_string(status),
      status_label: profile_status_label(profile)
    }
  end

  defp profile_fleet_entries(profile, mission_id, list, version_counts, latest_version) do
    version_counts
    |> Enum.sort_by(& &1.spacecraft_type_version, :desc)
    |> Enum.map(fn entry ->
      stale = stale_version?(entry, latest_version)

      %{
        label: "v#{entry.spacecraft_type_version} × #{entry.count}",
        href:
          if(stale,
            do: filter_path(mission_id, list, "profile:#{profile.spacecraft_type_id}"),
            else: nil
          )
      }
    end)
  end

  defp filter_path(mission_id, %ListParams{} = list, filter) do
    query = ListParams.to_query(%{list | page: 1}, filter: filter)
    ~p"/missions/#{mission_id}/spacecraft?#{query}"
  end

  defp range_label(%{page: page, page_size: size, total_count: total}) do
    first = (page - 1) * size + 1
    last = min(page * size, total)
    "#{first}–#{last} of #{total}"
  end

  defp profile_label(%{spacecraft_type_id: nil}, _profiles_by_id), do: "Not selected"

  defp profile_label(spacecraft, profiles_by_id) do
    case Map.get(profiles_by_id, spacecraft.spacecraft_type_id) do
      nil ->
        "Missing profile"

      profile ->
        "#{profile.display_name} v#{spacecraft.spacecraft_type_version || profile.version}"
    end
  end

  defp setup_status(%{scid: nil}, _latest_versions), do: :attention
  defp setup_status(%{spacecraft_type_id: nil}, _latest_versions), do: :attention

  defp setup_status(spacecraft, latest_versions) do
    if profile_drift?(spacecraft, latest_versions), do: :attention, else: :ready
  end

  defp setup_status_label(%{scid: nil}, _latest_versions), do: "Needs SCID"
  defp setup_status_label(%{spacecraft_type_id: nil}, _latest_versions), do: "Needs profile"

  defp setup_status_label(spacecraft, latest_versions) do
    if profile_drift?(spacecraft, latest_versions), do: "Profile drift", else: "Setup complete"
  end

  defp profile_drift?(spacecraft, latest_versions) do
    case Map.get(latest_versions, spacecraft.spacecraft_type_id) do
      nil ->
        false

      latest ->
        is_integer(spacecraft.spacecraft_type_version) and
          spacecraft.spacecraft_type_version < latest
    end
  end

  defp stale_version?(entry, latest_version) do
    is_integer(latest_version) and is_integer(entry.spacecraft_type_version) and
      entry.spacecraft_type_version < latest_version
  end

  defp profile_status(%{lifecycle_state: :active}), do: :ready
  defp profile_status(_profile), do: :attention

  defp profile_status_label(%{lifecycle_state: :active}), do: "Active"
  defp profile_status_label(_profile), do: "Archived"

  defp applications_summary(applications)
       when is_map(applications) and map_size(applications) > 0 do
    applications
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(", ", &humanize_application_key/1)
  end

  defp applications_summary(_), do: "None"

  defp humanize_application_key(key) when is_atom(key),
    do: key |> Atom.to_string() |> humanize_application_key()

  defp humanize_application_key(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

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
