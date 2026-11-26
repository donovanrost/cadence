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

  alias Cadence.Applications.SpacecraftConfiguration.CatalogAuthority
  alias Cadence.Applications.SpacecraftConfiguration.RevisionRow, as: ConfigurationRevisionRow
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  alias Cadence.Catalog
  alias Cadence.Ids
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @doc """
  Whether `scope` may save a spacecraft configuration draft in `mission_id`: a person, in this
  mission's scope, who may operate it. `authorize/3` runs exactly this, and the workspace
  snapshot's `can_save` reads it, so the two can't drift (lead on #620).
  """
  @spec may_save?(Scope.t(), binary()) :: boolean()
  def may_save?(scope, mission_id), do: permitted(scope, mission_id) == :ok

  defp permitted(
         %Scope{mission_id: scoped, user: %{user_id: user_id}} = scope,
         mission_id
       )
       when is_binary(user_id) and is_binary(mission_id) and
              (is_nil(scoped) or scoped == mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp permitted(_scope, _mission_id), do: {:error, :invalid_spacecraft_scope}

  @doc "`authorize/3` for the mission as a whole: the mission, when `scope` may save its drafts."
  @spec authorize_mission(Scope.t(), binary()) :: {:ok, struct()} | {:error, term()}
  def authorize_mission(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    with :ok <- permitted(scope, mission_id),
         do: Missions.fetch_mission(scope.organization_id, mission_id)
  end

  def authorize_mission(_scope, _mission_id), do: {:error, :invalid_spacecraft_scope}

  def authorize(%Scope{} = scope, mission_id, spacecraft_id)
      when is_binary(mission_id) and is_binary(spacecraft_id) do
    with :ok <- permitted(scope, mission_id),
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

  @doc "`latest/3` for many spacecraft in one query: `%{spacecraft_id => row}` (absent if none)."
  def latest_many(_organization_id, _mission_id, []), do: %{}

  def latest_many(organization_id, mission_id, spacecraft_ids) when is_list(spacecraft_ids) do
    from(row in ConfigurationRevisionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.spacecraft_id in ^spacecraft_ids,
      distinct: row.spacecraft_id,
      order_by: [asc: row.spacecraft_id, desc: row.version]
    )
    |> Repo.all()
    |> Map.new(&{&1.spacecraft_id, &1})
  end

  @doc "The latest saved row of every spacecraft in the mission that has one, in one query."
  @spec latest_for_mission(binary(), binary()) :: [struct()]
  def latest_for_mission(organization_id, mission_id) do
    from(row in ConfigurationRevisionRow,
      where: row.organization_id == ^organization_id and row.mission_id == ^mission_id,
      distinct: row.spacecraft_id,
      order_by: [asc: row.spacecraft_id, desc: row.version]
    )
    |> Repo.all()
  end

  @doc "Catalog references from each spacecraft’s latest saved configuration in this mission."
  def catalog_usage_entries(organization_id, mission_id) do
    latest =
      from(row in ConfigurationRevisionRow,
        where: row.organization_id == ^organization_id and row.mission_id == ^mission_id,
        distinct: row.spacecraft_id,
        order_by: [asc: row.spacecraft_id, desc: row.version],
        select: %{spacecraft_id: row.spacecraft_id, catalog_revision_id: row.catalog_revision_id}
      )

    from(row in subquery(latest),
      where: not is_nil(row.catalog_revision_id),
      select: row
    )
    |> Repo.all()
  end

  @doc """
  A new configuration revision that only moves the catalog (DECISIONS #65), written by a
  change-set apply for the running configuration `running_id`. Refused while the spacecraft has
  a newer configuration that isn't active yet (`:spacecraft_configuration_pending`): applying
  would activate it unreviewed, and superseding it would bury it.
  """
  @spec derive_catalog(binary(), binary(), binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, term()}
  def derive_catalog(organization_id, mission_id, running_id, catalog_revision_id, actor_id),
    do:
      derive(
        organization_id,
        mission_id,
        running_id,
        %{"catalog_revision_id" => catalog_revision_id},
        actor_id
      )

  @doc """
  The running configuration with `changes` (document keys: the catalog, the switches) as the
  spacecraft's next configuration revision, for a change-set apply (#36/#65, L22). Refused when a
  newer configuration than the running one exists.
  """
  def derive(organization_id, mission_id, running_id, changes, actor_id) when is_map(changes) do
    with {:ok, running} <- fetch(organization_id, mission_id, running_id),
         %{configuration_revision_id: ^running_id} = latest <-
           latest(organization_id, mission_id, running.spacecraft_id) ||
             {:error, :spacecraft_configuration_not_found} do
      document = Map.merge(running.document, changes)

      # The stored decom config follows, as a Save's does (ApplicationInputs.persist); its basis
      # changes with it, so the caller re-stamps the new revisions (restamp_bases/2).
      with :ok <-
             TelemetryDecom.project_configuration(
               organization_id,
               mission_id,
               running.spacecraft_id,
               document
             ) do
        insert_derived(organization_id, mission_id, running, latest, document, actor_id)
      end
    else
      {:error, reason} -> {:error, reason}
      _newer -> {:error, :spacecraft_configuration_pending}
    end
  end

  defp insert_derived(organization_id, mission_id, running, latest, document, actor_id) do
    catalog_revision_id = document["catalog_revision_id"]

    Repo.insert(
      ConfigurationRevisionRow.changeset(%{
        configuration_revision_id: Ids.new("spacecraft_configuration"),
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: running.spacecraft_id,
        version: latest.version + 1,
        catalog_revision_id: catalog_revision_id,
        document: document,
        content_sha256: ContentHash.term_sha256(document),
        application_basis: running.application_basis,
        created_by: actor_id
      })
    )
  end

  @doc """
  Stamps revisions `derive/5` just wrote with their spacecraft's current application basis (one read
  of the bases, one update), after the projection changed it. Without it the post-activation check
  (`TelemetryDecom`'s applied ids) would see every moved spacecraft as changed elsewhere.
  """
  def restamp_bases(_mission, []), do: :ok

  def restamp_bases(mission, rows) when is_list(rows) do
    bases = ConfigurationApplications.bases(mission, Enum.map(rows, & &1.spacecraft_id))

    Repo.query!(
      """
      UPDATE spacecraft_configuration_revisions AS r SET application_basis = v.basis
      FROM unnest($1::text[], $2::text[]) AS v(id, basis)
      WHERE r.configuration_revision_id = v.id
      """,
      [
        Enum.map(rows, & &1.configuration_revision_id),
        Enum.map(rows, &Map.fetch!(bases, &1.spacecraft_id))
      ]
    )

    :ok
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
    with :ok <- validate_catalog(mission, document["catalog_revision_id"]),
         # DECISIONS #65: a profile catalog is set through change sets only.
         :ok <- CatalogAuthority.check(mission, spacecraft, document["catalog_revision_id"]),
         # L22: switches a change set has set are written through change sets only.
         :ok <- CatalogAuthority.switches_check(spacecraft, document) do
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

  # Change sets are the ONLY writer of a craft's Telemetry and Commanding switches (DECISIONS #109):
  # a saved configuration takes the spacecraft's values (unset reads off) and ignores switch input.
  # CatalogAuthority.switches_check stays as the backstop at review.
  defp change_set_switches(document, spacecraft) do
    document
    |> Map.put("telemetry_enabled", Map.get(spacecraft, :telemetry_enabled) == true)
    |> Map.put("commanding_enabled", Map.get(spacecraft, :commanding_enabled) == true)
  end

  defp save_locked(scope, mission, spacecraft, expected_token, document) do
    mission_id = mission.mission_id
    spacecraft_id = spacecraft.spacecraft_id
    current = snapshot(mission, spacecraft)
    # The row as it is under the configuration lock, not the authorize read before it: a change
    # set that set a switch in between is what this save stores, and what its checks compare with.
    {:ok, locked} =
      SpacecraftStore.fetch_spacecraft(mission.organization_id, mission_id, spacecraft_id)

    document = change_set_switches(document, locked)

    with :ok <- exact_token(current.token, expected_token),
         :ok <- validate_references(mission, locked, document),
         {:ok, document} <-
           ConfigurationApplications.persist(scope, mission, locked, document) do
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
