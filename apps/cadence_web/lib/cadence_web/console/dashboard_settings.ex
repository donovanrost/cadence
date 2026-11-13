defmodule CadenceWeb.Console.DashboardSettings do
  @moduledoc """
  D14-D16 (fe-setup, docs/apogee/plans/dashboards-settings.md): a dashboard's settings and its
  shares and snapshots, over `Reads.Dashboards.Settings`, `SettingsAuthoring` and `Snapshots`.

  The wire speaks `with_data` for the domain's `authorized_runtime_data`, `defaults {time, scope}`
  for the stored `defaults` (`DashboardSettingsDefaults`), an `expires_at` date for the domain's
  hours, and `expected_version` alone (the lock revision stays server-side).
  """

  alias Cadence.Dashboards.{SettingsAuthoring, Snapshots}
  alias Cadence.Missions
  alias Cadence.Organizations
  alias Cadence.Reads.Dashboards.Settings
  alias CadenceWeb.Console.DashboardSettingsDefaults, as: Defaults

  @limits %{name: 120, description: 500, tags: 32, tag: 64}
  @visibility %{"with_data" => "authorized_runtime_data", "definition_only" => "definition_only"}
  @wire_visibility %{
    "authorized_runtime_data" => "with_data",
    "definition_only" => "definition_only"
  }
  @max_hours 8760

  @spec load(map(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def load(scope, mission, dashboard, params) do
    query = %{
      "after_share" => params["shares_after"],
      "after_snapshot" => params["snapshots_after"]
    }

    with {:ok, settings} <- read(scope, mission, dashboard, query) do
      base = base_url(scope.organization_id, mission)

      {:ok,
       %{
         dashboard: %{
           id: settings.dashboard_id,
           name: settings.name,
           description: settings.description,
           tags: settings.tags,
           lifecycle: settings.lifecycle,
           current_version: settings.document_version,
           published_version: settings.published_version
         },
         defaults: Defaults.to_wire(settings.defaults_json),
         limits: @limits,
         shares: page(settings.shares, &share(&1, base)),
         snapshots: page(settings.snapshots, &snapshot(&1, base))
       }}
    end
  end

  @doc "D15: `{name, description, tags, defaults, expected_version}` → `{version}`."
  def save(scope, mission, dashboard, body) do
    with {:ok, settings} <- read(scope, mission, dashboard, %{}),
         {:ok, defaults_json} <- Defaults.to_stored(settings.defaults_json, body["defaults"]),
         {:ok, fields} <- fields(body) do
      input =
        Map.merge(fields, %{
          "defaults_json" => defaults_json,
          "expected_version" => body["expected_version"],
          "expected_revision" => settings.revision
        })

      case SettingsAuthoring.execute(scope, mission, dashboard, "save_settings", input) do
        {:ok, receipt} -> {:ok, %{version: receipt.document_version}}
        error -> error
      end
    end
  end

  @doc "D16: `{data_visibility, expires_at | null}` → the share row."
  def create_share(scope, mission, dashboard, body) do
    with {:ok, visibility} <- visibility(body["data_visibility"]),
         {:ok, hours} <- hours(body["expires_at"]),
         {:ok, revision} <- revision(scope, mission, dashboard),
         {:ok, receipt} <-
           SettingsAuthoring.execute(scope, mission, dashboard, "create_share", %{
             "data_visibility" => visibility,
             "expires_in_hours" => hours,
             "expected_version" => revision.version,
             "expected_revision" => revision.revision
           }) do
      row(scope, mission, dashboard, :shares, receipt.resource_id)
    end
  end

  def revoke_share(scope, mission, dashboard, share_id) do
    with {:ok, revision} <- revision(scope, mission, dashboard),
         {:ok, _receipt} <-
           SettingsAuthoring.execute(scope, mission, dashboard, "revoke_share", %{
             "share_id" => share_id,
             "expected_version" => revision.version,
             "expected_revision" => revision.revision
           }) do
      row(scope, mission, dashboard, :shares, share_id)
    end
  end

  @doc "D16: `{data_visibility, runtime: {from, to, spacecraft_id | null}}` → the snapshot row."
  def create_snapshot(scope, mission, dashboard, body) do
    with {:ok, visibility} <- visibility(body["data_visibility"]),
         {:ok, snapshot} <-
           Snapshots.create(scope, mission, dashboard, %{
             "data_visibility" => visibility,
             "runtime" => body["runtime"]
           }) do
      row(scope, mission, dashboard, :snapshots, snapshot.dashboard_snapshot_id)
    end
  end

  def delete_snapshot(scope, mission, snapshot_id),
    do: Snapshots.delete(scope, mission, snapshot_id)

  defp read(scope, mission, dashboard, query) do
    case Settings.load(scope, mission, dashboard, query) do
      {:ok, settings} -> {:ok, settings}
      _unavailable -> {:error, :not_found}
    end
  end

  defp revision(scope, mission, dashboard) do
    with {:ok, settings} <- read(scope, mission, dashboard, %{}),
         do: {:ok, %{version: settings.document_version, revision: settings.revision}}
  end

  # The written row, found on the table's pages (25 a page, at most a few).
  defp row(scope, mission, dashboard, table, id, after_id \\ nil, pages \\ 20)
  defp row(_scope, _mission, _dashboard, _table, _id, _after, 0), do: {:error, :not_found}

  defp row(scope, mission, dashboard, table, id, after_id, pages) do
    key = if table == :shares, do: "shares_after", else: "snapshots_after"

    with {:ok, settings} <- load(scope, mission, dashboard, %{key => after_id}) do
      page = Map.fetch!(settings, table)

      case Enum.find(page.rows, &(&1.id == id)) do
        nil when page.next != nil ->
          row(scope, mission, dashboard, table, id, page.next, pages - 1)

        nil ->
          {:error, :not_found}

        found ->
          {:ok, found}
      end
    end
  end

  defp page(%{rows: rows, next: next}, fun), do: %{rows: Enum.map(rows, fun), next: next}

  defp share(share, base),
    do: %{
      id: share.id,
      url: base && base <> "/shares/" <> share.id,
      data_visibility: Map.get(@wire_visibility, share.data_visibility, share.data_visibility),
      state: share.state,
      expires_at: share.expires_at,
      created_at: share.created_at,
      created_by: share.created_by,
      revoked_by: Map.get(share, :revoked_by)
    }

  defp snapshot(snapshot, base),
    do: %{
      id: snapshot.id,
      url: base && base <> "/snapshots/" <> snapshot.id,
      version: snapshot.document_version,
      data_visibility:
        Map.get(@wire_visibility, snapshot.data_visibility, snapshot.data_visibility),
      window: snapshot.window,
      created_at: snapshot.created_at,
      created_by: snapshot.created_by
    }

  @doc "The console path dashboards' shared views hang off, or nil."
  @spec base_url(binary(), binary()) :: binary() | nil
  def base_url(organization_id, mission_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id) do
      "/console/#{segment(organization.slug)}/#{segment(mission.slug)}/telemetry/dashboards"
    else
      _unknown -> nil
    end
  end

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp fields(body) do
    errors =
      [
        text(body["name"], :name, 1..@limits.name),
        text(body["description"] || "", :description, 0..@limits.description),
        tags(body["tags"])
      ]
      |> Enum.filter(&match?({:error, _}, &1))
      |> Map.new(fn {:error, {key, message}} -> {key, message} end)

    if errors == %{},
      do:
        {:ok,
         %{
           "name" => String.trim(body["name"]),
           "description" => String.trim(body["description"] || ""),
           "tags" => body["tags"]
         }},
      else: {:error, {:invalid_params, errors}}
  end

  defp text(value, key, range) when is_binary(value) do
    if String.length(String.trim(value)) in range,
      do: :ok,
      else: {:error, {key, "must be #{range.first}–#{range.last} characters"}}
  end

  defp text(_value, key, _range), do: {:error, {key, "must be text"}}

  defp tags(tags) when is_list(tags) do
    ok? =
      length(tags) <= @limits.tags and
        Enum.all?(
          tags,
          &(is_binary(&1) and &1 == String.trim(&1) and &1 != "" and
              String.length(&1) <= @limits.tag)
        ) and Enum.uniq(tags) == tags

    if ok?, do: :ok, else: {:error, {:tags, "up to 32 distinct tags of 1–64 characters"}}
  end

  defp tags(_tags), do: {:error, {:tags, "must be a list"}}

  defp visibility(value) do
    case Map.fetch(@visibility, value) do
      {:ok, domain} ->
        {:ok, domain}

      :error ->
        {:error, {:invalid_params, %{data_visibility: "must be with_data or definition_only"}}}
    end
  end

  defp hours(nil), do: {:ok, nil}

  defp hours(value) when is_binary(value) do
    with {:ok, at, _offset} <- DateTime.from_iso8601(value),
         hours when hours in 1..@max_hours <- ceil_hours(at) do
      {:ok, hours}
    else
      _invalid ->
        {:error, {:invalid_params, %{expires_at: "must be a future date within a year"}}}
    end
  end

  defp hours(_value),
    do: {:error, {:invalid_params, %{expires_at: "must be a date-time or null"}}}

  defp ceil_hours(at) do
    seconds = DateTime.diff(at, DateTime.utc_now())
    if seconds <= 0, do: 0, else: div(seconds + 3599, 3600)
  end
end
