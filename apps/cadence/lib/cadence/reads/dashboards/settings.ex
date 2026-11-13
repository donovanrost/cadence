defmodule Cadence.Reads.Dashboards.Settings do
  @moduledoc "Authorized persisted settings and bounded sharing metadata, independent of frontend delivery."
  alias Cadence.Accounts

  alias Cadence.Dashboards.{
    Authoring,
    AuthoringDefaults,
    AuthoringInput,
    Document,
    Documents,
    SettingsInput,
    SettingsStore
  }

  alias Cadence.Repo

  def load(scope, mission, dashboard, params \\ %{}) do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, query} <- SettingsInput.query(params),
         {:ok, _} <- Documents.fetch(scope.organization_id, mission, dashboard) do
      SettingsStore.with_settings_snapshot(
        scope.organization_id,
        mission,
        dashboard,
        fn snapshot ->
          project(snapshot, query)
        end
      )
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp project(snapshot, query) do
    document = snapshot.document
    tags = Map.get(document.metadata, "tags", Map.get(document.metadata, :tags, []))

    with true <- valid_document?(snapshot, document, tags),
         {:ok, defaults} <- AuthoringDefaults.encode(document.defaults) do
      model(snapshot, document, tags, defaults, query)
    else
      _ -> Repo.rollback(:unavailable)
    end
  end

  defp valid_document?(snapshot, document, tags) do
    same_document?(snapshot, document) and
      SettingsInput.version?(snapshot.latest_version) and
      SettingsInput.version?(snapshot.lock_version) and
      SettingsInput.text?(document.name, 120, false) and
      SettingsInput.text?(document.description || "", 500, true) and SettingsInput.tags?(tags)
  end

  defp same_document?(snapshot, document) do
    document.organization_id == snapshot.organization_id and
      document.mission_id == snapshot.mission_id and
      document.dashboard_id == snapshot.dashboard_id and
      Document.version(document) == snapshot.latest_version
  end

  defp model(snapshot, document, tags, defaults, query) do
    org = snapshot.organization_id
    mission = snapshot.mission_id
    dashboard = snapshot.dashboard_id
    now = DateTime.utc_now()

    %{
      version: 1,
      organization_id: org,
      mission_id: mission,
      dashboard_id: dashboard,
      name: document.name,
      description: document.description || "",
      tags: tags,
      defaults_json: defaults,
      document_version: snapshot.latest_version,
      revision: snapshot.lock_version,
      published_version: snapshot.published_version,
      lifecycle: snapshot.lifecycle_state,
      loaded_at: timestamp(now),
      query: query,
      shares:
        org
        |> SettingsStore.shares(mission, dashboard, query["after_share"])
        |> project_page(&share(&1, now))
        |> with_creators(),
      snapshots:
        org
        |> SettingsStore.snapshots(mission, dashboard, query["after_snapshot"])
        |> project_page(&snapshot/1)
        |> with_creators(),
      deployments:
        org
        |> SettingsStore.deployments(mission, dashboard, query["after_deployment"])
        |> project_page(&deployment/1)
    }
  end

  defp share(share, now) do
    state =
      cond do
        share.revoked_at -> "revoked"
        share.expires_at && DateTime.compare(share.expires_at, now) != :gt -> "expired"
        true -> "active"
      end

    %{
      id: share.id,
      data_visibility: share.data_visibility,
      state: state,
      expires_at: timestamp(share.expires_at),
      created_at: timestamp(share.created_at),
      created_by: share.created_by,
      revoked_by: share.revoked_by
    }
  end

  # D16: the frozen window, or null for a snapshot taken without one (before Q5), never a guess.
  defp snapshot(snapshot) do
    context = snapshot.runtime_context || %{}

    window =
      if snapshot.data_semantics == "frozen_time_window" and is_binary(context["from"]) and
           is_binary(context["to"]),
         do: %{from: context["from"], to: context["to"]}

    snapshot
    |> Map.delete(:runtime_context)
    |> Map.merge(%{created_at: timestamp(snapshot.created_at), window: window})
  end

  # D14-D16: who made a share or snapshot, `{id, name | null, kind: "user"}`, or null.
  defp with_creators(%{rows: rows} = page) do
    names =
      rows
      |> Enum.flat_map(&[&1.created_by, Map.get(&1, :revoked_by)])
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Map.new(fn id ->
        case Accounts.fetch_user(id) do
          {:ok, user} -> {id, user.display_name || user.email}
          _not_a_user -> {id, nil}
        end
      end)

    %{page | rows: Enum.map(rows, &actors(&1, names))}
  end

  # D20: a share row also says who revoked it.
  defp actors(row, names) do
    row = %{row | created_by: creator(row.created_by, names)}

    if Map.has_key?(row, :revoked_by),
      do: %{row | revoked_by: creator(row.revoked_by, names)},
      else: row
  end

  defp creator(id, names) when is_binary(id),
    do: %{id: id, name: Map.get(names, id), kind: "user"}

  defp creator(_none, _names), do: nil

  defp deployment(deployment) do
    unless SettingsInput.text?(deployment.environment, 120, false),
      do: Repo.rollback(:unavailable)

    deployment
    |> Map.delete(:digest)
    |> Map.put(:digest_prefix, String.slice(deployment.digest, 0, 12))
    |> Map.put(:created_at, timestamp(deployment.created_at))
  end

  defp project_page(page, project), do: %{page | rows: Enum.map(page.rows, project)}
  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
