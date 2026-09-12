defmodule Cadence.Reads.Spacecraft.Directory do
  @moduledoc "Core spacecraft directory projection."

  alias Cadence.{SpacecraftStore, SpacecraftTypeStore}
  import Cadence.Reads.Spacecraft.Presentation

  @keys ~w(q sort dir page pageSize filter)

  def validate_params(params) do
    valid? =
      Enum.all?(params, fn {key, value} ->
        key in @keys and is_binary(value) and byte_size(value) <= 255 and String.valid?(value)
      end)

    if valid? and valid_filter?(Map.get(params, "filter", "")),
      do: :ok,
      else: {:error, :invalid_spacecraft_directory_query}
  end

  defp valid_filter?(value)
       when value in ["", "missing_scid", "missing_profile", "profile_drift"], do: true

  defp valid_filter?("profile:" <> id), do: id != "" and Regex.match?(~r/^[A-Za-z0-9_-]+$/, id)
  defp valid_filter?(_value), do: false

  def load(mission, params) do
    search = Map.get(params, "q", "")
    page_number = positive_integer(Map.get(params, "page"), 1)
    sort = if Map.get(params, "sort") == "display_name", do: :display_name, else: :scid
    direction = if Map.get(params, "dir") == "desc", do: :desc, else: :asc

    types = SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)
    summary = SpacecraftStore.fleet_summary(mission.organization_id, mission.mission_id)
    latest_versions = Map.new(types, &{&1.spacecraft_type_id, &1.version})
    filter = Map.get(params, "filter", "")

    options = [
      search: search,
      sort: {sort, direction},
      page: page_number,
      page_size: positive_integer(Map.get(params, "pageSize"), 50),
      filter: store_filter(filter, latest_versions)
    ]

    page =
      SpacecraftStore.list_spacecraft_page(mission.organization_id, mission.mission_id, options)

    last_page = max(1, ceil(page.total_count / page.page_size))

    page =
      if page.page > last_page do
        SpacecraftStore.list_spacecraft_page(
          mission.organization_id,
          mission.mission_id,
          Keyword.put(options, :page, last_page)
        )
      else
        page
      end

    drift_count =
      Enum.reduce(summary.profile_version_counts, 0, fn count, total ->
        latest = latest_versions[count.spacecraft_type_id]

        if is_integer(latest) and count.spacecraft_type_version < latest,
          do: total + count.count,
          else: total
      end)

    {:ok,
     %{
       "presentation" => %{
         "root" => %{"attrs" => %{"id" => "spacecraft-management-page", "class" => "space-y-6"}},
         "header" =>
           header("Spacecraft", "Manage spacecraft identities and their pinned profiles."),
         "breadcrumbs" => breadcrumbs(mission, "Spacecraft", spacecraft_path(mission, nil)),
         "summary_tiles" => summary_tiles(mission, summary, drift_count, params),
         "roster" =>
           Map.merge(roster(mission, page, summary), %{
             "search" => search,
             "sort_by" => to_string(sort),
             "sort_dir" => to_string(direction),
             "filter" => filter,
             "href" => spacecraft_path(mission, nil)
           }),
         "profiles" =>
           profile_preview(mission, types, summary.profile_version_counts, latest_versions)
       }
     }}
  end

  defp summary_tiles(mission, summary, drift_count, params) do
    filter = Map.get(params, "filter", "")

    [
      tile(
        "spacecraft-tile-all",
        "All spacecraft",
        summary.total,
        spacecraft_path(mission, nil),
        filter == "",
        false
      ),
      tile(
        "spacecraft-tile-missing-scid",
        "Missing SCID",
        summary.missing_scid,
        "#{spacecraft_path(mission, nil)}?filter=missing_scid",
        filter == "missing_scid",
        summary.missing_scid > 0
      ),
      tile(
        "spacecraft-tile-missing-profile",
        "Missing profile",
        summary.missing_profile,
        "#{spacecraft_path(mission, nil)}?filter=missing_profile",
        filter == "missing_profile",
        summary.missing_profile > 0
      ),
      tile(
        "spacecraft-tile-drift",
        "Profile drift",
        drift_count,
        "#{spacecraft_path(mission, nil)}?filter=profile_drift",
        filter == "profile_drift",
        drift_count > 0
      )
    ]
  end

  defp tile(id, label, value, href, active, warning),
    do: %{
      "id" => id,
      "label" => label,
      "value" => value,
      "href" => href,
      "active" => active,
      "warning" => warning
    }

  defp roster(mission, page, summary) do
    %{
      "fleet_empty" => summary.total == 0,
      "subtitle" => "#{summary.total} total · #{summary.missing_profile} missing profile",
      "new_spacecraft_href" => "#{spacecraft_path(mission, nil)}/new",
      "search" => "",
      "sort_by" => "scid",
      "sort_dir" => "asc",
      "filtered_empty" => page.items == [],
      "page" => page.page,
      "page_size" => page.page_size,
      "total_count" => page.total_count,
      "pagination_visible" => page.total_count > page.page_size,
      "range_label" => range_label(page),
      "previous_page" => max(page.page - 1, 1),
      "next_page" => page.page + 1,
      "previous_disabled" => page.page <= 1,
      "next_disabled" => page.page * page.page_size >= page.total_count,
      "rows" => Enum.map(page.items, &spacecraft_row(&1, mission))
    }
  end

  defp range_label(%{total_count: 0}), do: "0 spacecraft"

  defp range_label(page),
    do:
      "#{(page.page - 1) * page.page_size + 1}–#{min(page.page * page.page_size, page.total_count)} of #{page.total_count}"

  defp spacecraft_row(spacecraft, mission) do
    profile_label =
      if spacecraft.spacecraft_type_id, do: spacecraft.spacecraft_type_id, else: "Not set"

    ready? = is_integer(spacecraft.scid) and not is_nil(spacecraft.spacecraft_type_id)

    %{
      "id" => "spacecraft-#{spacecraft.spacecraft_id}",
      "actions_id" => "#{spacecraft.spacecraft_id}-actions",
      "display_name" => spacecraft.display_name,
      "scid_label" =>
        if(is_nil(spacecraft.scid), do: "Not set", else: to_string(spacecraft.scid)),
      "scid_missing" => is_nil(spacecraft.scid),
      "profile_label" => profile_label,
      "status" => if(ready?, do: "ready", else: "attention"),
      "status_label" => if(ready?, do: "Ready", else: "Attention"),
      "href" => spacecraft_path(mission, spacecraft.spacecraft_id),
      "identity_href" => identity_path(mission, spacecraft)
    }
  end

  defp profile_preview(mission, profiles, counts, latest) do
    rows =
      profiles
      |> Enum.take(5)
      |> Enum.map(fn profile ->
        %{
          "id" => "spacecraft-profile-preview-#{profile.spacecraft_type_id}",
          "display_name" => profile.display_name,
          "href" => profile_path(mission, profile.spacecraft_type_id),
          "fleet_entries" => fleet_entries(profile, counts, latest, mission),
          "protocols" =>
            "#{String.upcase(to_string(profile.downlink_protocol))} / #{String.upcase(to_string(profile.uplink_protocol))}",
          "applications" => application_summary(profile.applications),
          "status" => "ready",
          "status_label" => "Current"
        }
      end)

    %{
      "empty" => profiles == [],
      "truncated" => length(profiles) > 5,
      "subtitle" => "#{length(profiles)} total",
      "new_profile_href" => "#{profiles_path(mission)}/new",
      "all_profiles_href" => profiles_path(mission),
      "rows" => rows
    }
  end

  defp fleet_entries(profile, counts, latest, mission) do
    counts
    |> Enum.filter(&(&1.spacecraft_type_id == profile.spacecraft_type_id))
    |> Enum.map(fn count ->
      %{
        "label" => "v#{count.spacecraft_type_version} × #{count.count}",
        "href" =>
          if(count.spacecraft_type_version != Map.get(latest, profile.spacecraft_type_id),
            do:
              "#{spacecraft_path(mission, nil)}?#{URI.encode_query(%{"filter" => "profile:#{profile.spacecraft_type_id}"})}",
            else: nil
          )
      }
    end)
  end

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> min(integer, 1_000_000)
      _other -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp store_filter("missing_scid", _latest), do: :missing_scid
  defp store_filter("missing_profile", _latest), do: :missing_profile
  defp store_filter("profile_drift", latest), do: {:stale_versions, latest}
  defp store_filter("profile:" <> id, _latest), do: {:profile, id}
  defp store_filter("", _latest), do: nil
end
