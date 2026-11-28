defmodule Cadence.Applications.SpacecraftConfiguration.Drafts do
  @moduledoc "Authorized, versioned spacecraft configuration drafts; saving never activates them."

  alias Cadence.Applications.ConfigurationLock

  alias Cadence.Auth.Policy
  alias Cadence.Auth.Scope
  alias Cadence.Platform.ContentHash
  alias Cadence.Platform.ScopedReadUpdates

  alias Cadence.Applications.SpacecraftConfiguration.ApplicationInputs,
    as: ConfigurationApplications

  alias Cadence.Applications.SpacecraftConfiguration.Assignments
  alias Cadence.Applications.SpacecraftConfiguration.CatalogAuthority
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  alias Cadence.Catalog
  alias Cadence.Catalog.CompositionPins
  alias Cadence.Missions
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

  defdelegate saved_for_mission?(organization_id, mission_id), to: Assignments, as: :saved?
  defdelegate fetch_many(organization_id, mission_id, ids), to: Assignments
  defdelegate latest_many(organization_id, mission_id, spacecraft_ids), to: Assignments
  defdelegate latest_references(organization_id, mission_id, spacecraft_ids), to: Assignments
  defdelegate latest_for_mission(organization_id, mission_id), to: Assignments
  defdelegate catalog_usage_entries(organization_id, mission_id), to: Assignments
  defdelegate saved_on_catalog(organization_id, mission_id, catalog_revision_id), to: Assignments
  defdelegate latest_versions(organization_id, mission_id, spacecraft_ids), to: Assignments
  defdelegate history(organization_id, mission_id, spacecraft_id), to: Assignments

  def latest(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> latest_many(mission_id, [spacecraft_id])
    |> Map.get(spacecraft_id)
  end

  def fetch(organization_id, mission_id, id) do
    case fetch_many(organization_id, mission_id, [id]) do
      %{^id => row} -> {:ok, row}
      %{} -> {:error, :spacecraft_configuration_not_found}
    end
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

    saved = if row, do: row.document, else: default_document(mission, spacecraft)
    changed = row && row.application_basis != application_basis

    %{
      row: row,
      document: saved,
      saved: saved,
      application_basis: application_basis,
      external_changes: changed == true,
      token: token(mission, spacecraft, row, application_basis)
    }
  end

  @doc """
  The token of a spacecraft's configuration: what a client holds while it edits or reviews, so a
  change underneath refuses as stale. The one formula `snapshot/2` and `tokens/2` share.
  """
  @spec token(map(), map(), struct() | nil, binary()) :: binary()
  def token(mission, spacecraft, row, application_basis) do
    ContentHash.term_sha256(
      {1, mission.organization_id, mission.mission_id, spacecraft.spacecraft_id,
       row && row.configuration_revision_id, application_basis, spacecraft.scid,
       spacecraft.spacecraft_type_id, spacecraft.spacecraft_type_version}
    )
  end

  @doc """
  The tokens (`spacecraft_id => token`) of many spacecraft, equal to each `snapshot/2` token, in a
  fixed number of queries: the application basis is read for all of them at once, and nothing
  else a snapshot loads (document, profile, telemetry config) is part of a token. `entries` is
  `[{spacecraft, latest_row_or_nil}]`.
  """
  @spec tokens(map(), [{map(), struct() | nil}]) :: %{binary() => binary()}
  def tokens(_mission, []), do: %{}

  def tokens(mission, entries) do
    bases =
      ConfigurationApplications.bases(mission, Enum.map(entries, &elem(&1, 0).spacecraft_id))

    Map.new(entries, fn {spacecraft, row} ->
      {spacecraft.spacecraft_id,
       token(mission, spacecraft, row, Map.fetch!(bases, spacecraft.spacecraft_id))}
    end)
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

  defp default_document(mission, spacecraft) do
    {:ok, profile} = SpacecraftStore.fetch_pinned_profile(mission, spacecraft)
    Map.put(ConfigurationInput.empty(), "protocol", ConfigurationInput.from_profile(profile))
  end

  defp validate_references(mission, spacecraft, document) do
    with {:ok, catalog} <- validate_catalog(mission, document["catalog_revision_id"]),
         # DECISIONS #65: a profile catalog is set through change sets only.
         :ok <- CatalogAuthority.check(mission, spacecraft, document["catalog_revision_id"]),
         # L22: switches a change set has set are written through change sets only.
         :ok <- CatalogAuthority.switches_check(spacecraft, document),
         :ok <- validate_source(mission, spacecraft, document["telemetry_source_endpoint_id"]) do
      {:ok, catalog}
    end
  end

  defp validate_catalog(_mission, nil), do: {:ok, nil}

  defp validate_catalog(mission, id) do
    case Catalog.fetch_revision(mission.organization_id, mission.mission_id, id) do
      {:ok, catalog} -> {:ok, catalog}
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
         {:ok, catalog} <- validate_references(mission, locked, document),
         {:ok, document} <-
           ConfigurationApplications.persist(scope, mission, locked, document, catalog) do
      version = if current.row, do: current.row.version + 1, else: 1

      row =
        Assignments.new(
          mission,
          spacecraft_id,
          version,
          document,
          scope.user.user_id,
          model_evidence(mission, catalog)
        )

      basis = ConfigurationApplications.basis(mission, spacecraft_id)
      [saved] = Assignments.append([%{row | application_basis: basis}])
      {:ok, saved}
    end
  end

  defp model_evidence(_mission, nil), do: %{}

  defp model_evidence(mission, catalog) do
    composition =
      case CompositionPins.for_catalog_revision(
             mission.organization_id,
             mission.mission_id,
             catalog.catalog_revision_id
           ) do
        {:ok, id} -> id
        {:error, :none} -> nil
      end

    %{composition_id: composition, effective_revision_id: catalog.mission_model_revision_id}
  end
end
