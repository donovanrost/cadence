defmodule Cadence.Applications.SpacecraftConfiguration.Drafts do
  @moduledoc "Authorized, versioned spacecraft configuration drafts; saving never activates them."

  import Ecto.Query

  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.TelemetryDecom

  alias Cadence.Auth.Policy
  alias Cadence.Auth.Scope
  alias Cadence.Platform.ContentHash
  alias Cadence.Platform.ScopedReadUpdates

  alias Cadence.Applications.SpacecraftConfiguration.ApplicationInputs,
    as: ConfigurationApplications

  alias Cadence.Applications.SpacecraftConfiguration.RevisionRow, as: ConfigurationRevisionRow
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  alias Cadence.Catalog
  alias Cadence.Ids
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  def authorize(
        %Scope{mission_id: scoped, user: %{user_id: user_id}} = scope,
        mission_id,
        spacecraft_id
      )
      when is_binary(user_id) and is_binary(mission_id) and is_binary(spacecraft_id) and
             (is_nil(scoped) or scoped == mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(scope.organization_id, mission_id, spacecraft_id) do
      {:ok, mission, spacecraft}
    end
  end

  def authorize(_, _, _), do: {:error, :invalid_spacecraft_scope}

  def legacy_apply_allowed(org, mission) do
    if saved_for_mission?(org, mission),
      do: {:error, :spacecraft_configuration_review_required},
      else: :ok
  end

  def saved_for_mission?(organization_id, mission_id) do
    Repo.exists?(
      from(row in ConfigurationRevisionRow,
        where: row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )
    )
  end

  def latest(organization_id, mission_id, spacecraft_id) do
    ConfigurationRevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.spacecraft_id == ^spacecraft_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Spacecraft whose latest saved configuration uses this catalog, bounded independently of fleet ordering."
  def catalog_usage_ids(organization_id, mission_id, catalog_id) do
    latest =
      from(row in ConfigurationRevisionRow,
        where: row.organization_id == ^organization_id and row.mission_id == ^mission_id,
        distinct: row.spacecraft_id,
        order_by: [asc: row.spacecraft_id, desc: row.version],
        select: %{spacecraft_id: row.spacecraft_id, catalog_revision_id: row.catalog_revision_id}
      )

    from(row in subquery(latest),
      where: row.catalog_revision_id == ^catalog_id,
      order_by: row.spacecraft_id,
      limit: 100,
      select: row.spacecraft_id
    )
    |> Repo.all()
  end

  def fetch(organization_id, mission_id, id) do
    case Repo.get_by(ConfigurationRevisionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           configuration_revision_id: id
         ) do
      nil -> {:error, :spacecraft_configuration_not_found}
      row -> {:ok, row}
    end
  end

  def history(organization_id, mission_id, spacecraft_id) do
    ConfigurationRevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.spacecraft_id == ^spacecraft_id
    )
    |> order_by([row], desc: row.version)
    |> limit(20)
    |> Repo.all()
  end

  # Callers combine this with other workspace reads under the configuration lock.
  def snapshot(mission, spacecraft) do
    row = latest(mission.organization_id, mission.mission_id, spacecraft.spacecraft_id)

    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecraft(
        mission.organization_id,
        mission.mission_id,
        spacecraft.spacecraft_id
      )

    application_basis = ConfigurationApplications.basis(mission, spacecraft.spacecraft_id)

    {:ok, profile} = SpacecraftStore.fetch_pinned_profile(mission, spacecraft)
    config = optional_telemetry(mission, spacecraft)
    saved = if row, do: row.document, else: legacy_document(config, profile)
    changed = row && row.application_basis != application_basis
    document = if changed, do: overlay_telemetry(saved, config), else: saved

    %{
      row: row,
      document: document,
      saved: saved,
      application_basis: application_basis,
      external_changes: changed == true,
      token:
        ContentHash.term_sha256(
          {1, mission.organization_id, mission.mission_id, spacecraft.spacecraft_id,
           row && row.configuration_revision_id, application_basis, spacecraft.scid,
           spacecraft.spacecraft_type_id, spacecraft.spacecraft_type_version}
        )
    }
  end

  def save(scope, mission_id, spacecraft_id, expected_token, input) do
    with {:ok, mission, spacecraft} <- authorize(scope, mission_id, spacecraft_id),
         {:ok, document} <- ConfigurationInput.decode(input) do
      ConfigurationLock.run(scope.organization_id, mission_id, fn ->
        save_locked(scope, mission, spacecraft, expected_token, document)
      end)
      |> ScopedReadUpdates.publish_result(
        :spacecraft_configuration_changed,
        scope.organization_id,
        mission_id
      )
    end
  end

  def exact_token(token, token) when is_binary(token), do: :ok
  def exact_token(_, _), do: {:error, :spacecraft_configuration_changed}

  defp legacy_document(config, profile) do
    ConfigurationInput.empty()
    |> Map.put("protocol", ConfigurationInput.from_profile(profile))
    |> Map.put("commanding_enabled", not is_nil(config))
    |> overlay_telemetry(config)
  end

  defp overlay_telemetry(document, nil), do: document

  defp overlay_telemetry(document, config) do
    Map.merge(document, %{
      "catalog_revision_id" => config.catalog_revision_id,
      "telemetry_enabled" => config.enabled,
      "telemetry_source_endpoint_id" => config.source_endpoint_id,
      "handled_apids" => config.handled_apids
    })
  end

  defp optional_telemetry(mission, spacecraft) do
    case TelemetryDecom.fetch_config(
           mission.organization_id,
           mission.mission_id,
           spacecraft.spacecraft_id
         ) do
      {:ok, config} -> config
      {:error, :not_configured} -> nil
    end
  end

  defp validate_references(mission, spacecraft, document) do
    with :ok <- validate_catalog(mission, document["catalog_revision_id"]) do
      validate_source(mission, spacecraft, document["telemetry_source_endpoint_id"])
    end
  end

  defp validate_catalog(_mission, nil), do: :ok

  defp validate_catalog(mission, id) do
    case Catalog.fetch_revision(mission.organization_id, mission.mission_id, id) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :spacecraft_catalog_unavailable}
    end
  end

  defp validate_source(_mission, _spacecraft, nil), do: :ok

  defp validate_source(mission, spacecraft, id) do
    case SourceEndpoints.fetch_source_endpoint(mission.organization_id, mission.mission_id, id) do
      {:ok, %{spacecraft_id: spacecraft_id}} when spacecraft_id == spacecraft.spacecraft_id -> :ok
      _ -> {:error, :spacecraft_packet_input_unavailable}
    end
  end

  defp save_locked(scope, mission, spacecraft, expected_token, document) do
    mission_id = mission.mission_id
    spacecraft_id = spacecraft.spacecraft_id
    current = snapshot(mission, spacecraft)

    with :ok <- exact_token(current.token, expected_token),
         :ok <- validate_references(mission, spacecraft, document),
         {:ok, document} <-
           ConfigurationApplications.persist(scope, mission, spacecraft, document) do
      updated = snapshot(mission, spacecraft)

      Repo.insert(
        ConfigurationRevisionRow.changeset(%{
          configuration_revision_id: Ids.new("spacecraft_configuration"),
          organization_id: scope.organization_id,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id,
          version: if(current.row, do: current.row.version + 1, else: 1),
          catalog_revision_id: document["catalog_revision_id"],
          document: document,
          content_sha256: ContentHash.term_sha256(document),
          application_basis: updated.application_basis,
          created_by: scope.user.user_id
        })
      )
    end
  end
end
