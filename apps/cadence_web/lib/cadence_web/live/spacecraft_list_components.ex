defmodule CadenceWeb.SpacecraftListComponents do
  @moduledoc """
  Sections of the exception-first spacecraft management page: filter tiles,
  the profile fleet overview, and the searchable roster.
  """

  use CadenceWeb, :html

  alias CadenceWeb.ListParams

  attr :mission_id, :string, required: true
  attr :summary, :map, required: true
  attr :drift_count, :integer, required: true
  attr :list, ListParams, required: true
  attr :filter, :any, required: true

  def summary_tiles(assigns) do
    ~H"""
    <div id="spacecraft-setup-summary" class="grid gap-3 md:grid-cols-4">
      <.stat_tile
        id="spacecraft-tile-all"
        label="Vehicles"
        value={@summary.total}
        patch={filter_path(@mission_id, @list, nil)}
        active={is_nil(@filter)}
      />
      <.stat_tile
        id="spacecraft-tile-missing-scid"
        label="Missing SCID"
        value={@summary.missing_scid}
        patch={filter_path(@mission_id, @list, "missing_scid")}
        active={@filter == :missing_scid}
        class={@summary.missing_scid > 0 && "border-l-2 border-l-warning/60"}
      />
      <.stat_tile
        id="spacecraft-tile-missing-profile"
        label="Missing profile"
        value={@summary.missing_profile}
        patch={filter_path(@mission_id, @list, "missing_profile")}
        active={@filter == :missing_profile}
        class={@summary.missing_profile > 0 && "border-l-2 border-l-warning/60"}
      />
      <.stat_tile
        id="spacecraft-tile-drift"
        label="Profile drift"
        value={@drift_count}
        patch={filter_path(@mission_id, @list, "drift")}
        active={@filter == :drift}
        class={@drift_count > 0 && "border-l-2 border-l-warning/60"}
      />
    </div>
    """
  end

  attr :mission_id, :string, required: true
  attr :rows, :any, required: true
  attr :list, ListParams, required: true
  attr :profiles_empty?, :boolean, required: true
  attr :profiles_truncated?, :boolean, required: true
  attr :profile_count, :integer, required: true
  attr :drift_count, :integer, required: true
  attr :version_counts_by_profile, :map, required: true
  attr :latest_versions, :map, required: true

  def profiles_card(assigns) do
    ~H"""
    <.card
      id="spacecraft-profiles-card"
      heading="Profiles"
      subtitle={"#{@profile_count} total · #{@drift_count} drift warning"}
      padding={if @profiles_empty?, do: :default, else: :none}
    >
      <:actions>
        <.button navigate={~p"/missions/#{@mission_id}/spacecraft/profiles/new"} class="gap-1">
          <.icon name="hero-plus" class="h-4 w-4" /> New profile
        </.button>
      </:actions>

      <%= if @profiles_empty? do %>
        <.empty_state
          title="No profiles yet"
          description="Create a profile to reuse frame and packet interpretation settings across spacecraft."
          action_label="Create the first profile"
          action_navigate={~p"/missions/#{@mission_id}/spacecraft/profiles/new"}
        />
      <% else %>
        <.table
          id="spacecraft-profiles-preview-table"
          body_id="spacecraft-profile-previews"
          rows={@rows}
        >
          <:col :let={profile} label="Name" class="font-medium">
            <.link
              navigate={~p"/missions/#{@mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"}
              class="text-primary hover:underline"
            >
              {profile.display_name}
            </.link>
          </:col>
          <:col :let={profile} label="Fleet" mono class="text-base-content/70">
            <.fleet_label
              mission_id={@mission_id}
              profile={profile}
              list={@list}
              version_counts={Map.get(@version_counts_by_profile, profile.spacecraft_type_id, [])}
              latest_version={Map.get(@latest_versions, profile.spacecraft_type_id)}
            />
          </:col>
          <:col :let={profile} label="Protocols" mono class="uppercase text-primary/80">
            {profile.downlink_protocol} / {profile.uplink_protocol}
          </:col>
          <:col :let={profile} label="Applications" class="text-sm text-base-content/70">
            {applications_summary(profile.applications)}
          </:col>
          <:col :let={profile} label="State">
            <.status_badge status={profile_status(profile)} label={profile_status_label(profile)} />
          </:col>
        </.table>

        <div :if={@profiles_truncated?} class="border-t border-base-300 px-4 py-3 text-right">
          <.button variant={:ghost} navigate={~p"/missions/#{@mission_id}/spacecraft/profiles"}>
            View all profiles
          </.button>
        </div>
      <% end %>
    </.card>
    """
  end

  attr :mission_id, :string, required: true
  attr :profile, :any, required: true
  attr :list, ListParams, required: true
  attr :version_counts, :list, required: true
  attr :latest_version, :any, required: true

  defp fleet_label(%{version_counts: []} = assigns) do
    ~H"""
    <span class="text-base-content/50">Unused</span>
    """
  end

  defp fleet_label(assigns) do
    assigns =
      assign(
        assigns,
        :entries,
        Enum.sort_by(assigns.version_counts, & &1.spacecraft_type_version, :desc)
      )

    ~H"""
    <span :for={{entry, index} <- Enum.with_index(@entries)}>
      <span :if={index > 0} class="text-base-content/40">·</span>
      <%= if stale_version?(entry, @latest_version) do %>
        <.link
          patch={
            filter_path(@mission_id, @list, "profile:#{@profile.spacecraft_type_id}")
          }
          class="text-warning hover:underline"
        >
          v{entry.spacecraft_type_version} × {entry.count}
        </.link>
      <% else %>
        v{entry.spacecraft_type_version} × {entry.count}
      <% end %>
    </span>
    """
  end

  attr :mission_id, :string, required: true
  attr :rows, :any, required: true
  attr :list, ListParams, required: true
  attr :filter, :any, required: true
  attr :roster, :map, required: true
  attr :fleet_empty?, :boolean, required: true
  attr :summary, :map, required: true
  attr :profiles_by_id, :map, required: true
  attr :latest_versions, :map, required: true

  def roster_card(assigns) do
    ~H"""
    <.card
      id="spacecraft-vehicles-card"
      heading="Vehicles"
      subtitle={"#{@summary.total} total · #{@summary.missing_profile} missing profile"}
      padding={if @fleet_empty?, do: :default, else: :none}
    >
      <:actions>
        <.button navigate={~p"/missions/#{@mission_id}/spacecraft/new"} class="gap-1">
          <.icon name="hero-plus" class="h-4 w-4" /> New spacecraft
        </.button>
      </:actions>

      <%= if @fleet_empty? do %>
        <.empty_state
          title="No spacecraft yet"
          description="Register the first spacecraft for this mission."
          action_label="Register the first spacecraft"
          action_navigate={~p"/missions/#{@mission_id}/spacecraft/new"}
        />
      <% else %>
        <.toolbar id="spacecraft-roster-toolbar" search={@list.q} placeholder="Search name or SCID" />
        <.table
          id="spacecraft-vehicles-table"
          body_id="spacecraft-vehicles"
          rows={@rows}
          sort_by={@list.sort}
          sort_dir={@list.dir}
        >
          <:col :let={spacecraft} label="Name" sort="display_name" class="font-medium">
            <.link
              navigate={~p"/missions/#{@mission_id}/spacecraft/#{spacecraft.spacecraft_id}"}
              class="text-primary hover:underline"
            >
              {spacecraft.display_name}
            </.link>
          </:col>
          <:col :let={spacecraft} label="SCID" sort="scid" mono>
            <span class={
              if(spacecraft.scid, do: "text-primary/80", else: "text-base-content/50 italic")
            }>
              {spacecraft.scid || "Not set"}
            </span>
          </:col>
          <:col :let={spacecraft} label="Profile" class="text-sm text-base-content/70">
            {profile_label(spacecraft, @profiles_by_id)}
          </:col>
          <:col :let={spacecraft} label="Setup">
            <.status_badge
              status={setup_status(spacecraft, @latest_versions)}
              label={setup_status_label(spacecraft, @latest_versions)}
            />
          </:col>
          <:col :let={spacecraft} label="Actions" align={:right}>
            <.action_menu id={"#{spacecraft.spacecraft_id}-actions"}>
              <:action>
                <.link navigate={~p"/missions/#{@mission_id}/spacecraft/#{spacecraft.spacecraft_id}"}>
                  View
                </.link>
              </:action>
              <:action>
                <.link navigate={
                  ~p"/missions/#{@mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
                }>
                  Identity
                </.link>
              </:action>
            </.action_menu>
          </:col>
        </.table>
        <%!-- The table's :empty slot can't see stream emptiness; use the page total. --%>
        <p :if={@roster.total_count == 0} class="py-6 text-center text-sm text-base-content/70">
          No spacecraft match the current search or filter.
        </p>
        <.pagination
          id="spacecraft-roster-pagination"
          page={@roster.page}
          page_size={@roster.page_size}
          total_count={@roster.total_count}
        />
      <% end %>
    </.card>
    """
  end

  @doc "Patch path for the roster with a (possibly nil) filter; resets to page 1."
  def filter_path(mission_id, %ListParams{} = list, filter) do
    query = ListParams.to_query(%{list | page: 1}, filter: filter)
    ~p"/missions/#{mission_id}/spacecraft?#{query}"
  end

  defp stale_version?(entry, latest_version) do
    is_integer(latest_version) and is_integer(entry.spacecraft_type_version) and
      entry.spacecraft_type_version < latest_version
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
end
