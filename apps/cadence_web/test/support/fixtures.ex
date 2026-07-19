defmodule CadenceWeb.TestFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Accounts.{
    OrganizationMembership,
    OrganizationMembershipRow,
    Password,
    User,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.Dashboards.{Document, Placement, PlacementEditor}
  alias Cadence.Ids
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.{Spacecraft, SpacecraftType}

  alias Cadence.Repo

  @default_password "durable-password-123"

  def default_password, do: @default_password

  @spec persist_user!(keyword()) :: User.t()
  def persist_user!(opts \\ []) do
    email = Keyword.get(opts, :email, "user-#{System.unique_integer([:positive])}@example.com")
    password = Keyword.get(opts, :password, @default_password)
    display_name = Keyword.get(opts, :display_name, "Durable User")
    capabilities = Keyword.get(opts, :capabilities, [])

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: display_name,
        capabilities: capabilities,
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  @spec persist_org!(keyword()) :: Organization.t()
  def persist_org!(opts \\ []) do
    slug = Keyword.get(opts, :slug, "org-#{System.unique_integer([:positive])}")
    display_name = Keyword.get(opts, :display_name, "Cadence Org")

    org = Organization.new(%{display_name: display_name, slug: slug})
    assert {:ok, persisted} = Cadence.persist_organization(org)
    persisted
  end

  @spec grant_membership!(User.t(), Organization.t(), keyword()) :: OrganizationMembership.t()
  def grant_membership!(%User{} = user, %Organization{} = org, opts \\ []) do
    role = Keyword.get(opts, :role, :member)

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: role,
        lifecycle_state: :active
      })

    assert {:ok, _row} = Repo.insert(OrganizationMembershipRow.changeset(membership))
    membership
  end

  @spec member_session_token!(User.t()) :: binary()
  def member_session_token!(%User{email: email}) do
    assert {:ok, session} = Cadence.sign_in(email, @default_password)
    session.session_token
  end

  @spec member_conn(User.t()) :: Plug.Conn.t()
  def member_conn(%User{} = user) do
    token = member_session_token!(user)
    Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{user_session_token: token})
  end

  @spec persist_mission!(Cadence.Organizations.Organization.t(), keyword()) :: Mission.t()
  def persist_mission!(org, opts \\ []) do
    slug = Keyword.get(opts, :slug, "mission-#{System.unique_integer([:positive])}")
    display_name = Keyword.get(opts, :display_name, "Fixture Mission")

    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.Missions.persist_mission(mission)
    persisted
  end

  @spec persist_spacecraft!(Mission.t(), keyword()) :: Spacecraft.t()
  def persist_spacecraft!(%Mission{} = mission, opts \\ []) do
    display_name =
      Keyword.get(opts, :display_name, "Spacecraft-#{System.unique_integer([:positive])}")

    spacecraft =
      Spacecraft.new(%{
        mission_id: mission.mission_id,
        display_name: display_name,
        scid: Keyword.get(opts, :scid),
        spacecraft_type_id: Keyword.get(opts, :spacecraft_type_id),
        spacecraft_type_version: Keyword.get(opts, :spacecraft_type_version)
      })

    assert {:ok, persisted} = Cadence.persist_spacecraft(mission.organization_id, spacecraft)
    persisted
  end

  @spec persist_dashboard_document!(Mission.t(), keyword()) :: Document.t()
  def persist_dashboard_document!(%Mission{} = mission, opts \\ []) do
    document = %Document{
      dashboard_id: Keyword.get(opts, :dashboard_id, Ids.new("dashboard")),
      organization_id: mission.organization_id,
      mission_id: mission.mission_id,
      name: Keyword.get(opts, :name, "Dashboard-#{System.unique_integer([:positive])}"),
      description: Keyword.get(opts, :description),
      placements:
        opts
        |> Keyword.get(:placements, widget_specs_to_placements(Keyword.get(opts, :widgets, [])))
        |> Enum.map(&normalize_dashboard_placement!/1)
    }

    assert {:ok, persisted} =
             Cadence.Dashboards.persist_document(mission.organization_id, document)

    persisted
  end

  @spec persist_spacecraft_profile!(Mission.t(), keyword()) :: SpacecraftType.t()
  def persist_spacecraft_profile!(%Mission{} = mission, opts \\ []) do
    profile =
      SpacecraftType.new(%{
        mission_id: mission.mission_id,
        display_name:
          Keyword.get(opts, :display_name, "Profile-#{System.unique_integer([:positive])}"),
        downlink_protocol: Keyword.get(opts, :downlink_protocol, :tm),
        uplink_protocol: Keyword.get(opts, :uplink_protocol, :tc),
        packet_protocol: Keyword.get(opts, :packet_protocol, :space_packet),
        frame_parameters:
          Keyword.get(opts, :frame_parameters, %{
            "frame_size" => 1024,
            "secondary_header_length" => 0,
            "ocf_length" => 0
          }),
        applications: Keyword.get(opts, :applications, %{"telemetry_decom" => %{}})
      })

    assert {:ok, persisted} = Cadence.persist_spacecraft_type(mission.organization_id, profile)
    persisted
  end

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Database, as: CatalogDatabase
  alias Cadence.Catalog.ImportRun
  alias Cadence.Catalog.Revision, as: CatalogRevision

  @spec persist_catalog_database!(Mission.t(), keyword()) :: CatalogDatabase.t()
  def persist_catalog_database!(%Mission{} = mission, opts \\ []) do
    assert {:ok, database} =
             Catalog.create_database(mission.organization_id, mission.mission_id, %{
               name: Keyword.get(opts, :name, "Mission Database"),
               slug: Keyword.get(opts, :slug, "mission-database"),
               description: Keyword.get(opts, :description),
               catalog_family: Keyword.get(opts, :catalog_family, :combined),
               default_importer_key: Keyword.get(opts, :default_importer_key, "cadence_yaml"),
               created_by: Keyword.get(opts, :created_by, %{}),
               metadata: Keyword.get(opts, :metadata, %{})
             })

    database
  end

  @spec persist_catalog_artifact!(Mission.t(), keyword()) :: Artifact.t()
  def persist_catalog_artifact!(%Mission{} = mission, opts \\ []) do
    artifact =
      Artifact.new(%{
        mission_id: mission.mission_id,
        catalog_database_id: Keyword.get(opts, :catalog_database_id),
        catalog_family: Keyword.get(opts, :catalog_family, :combined),
        artifact_name: Keyword.get(opts, :artifact_name, "mission.yaml"),
        format_key: Keyword.get(opts, :format_key, "cadence_yaml"),
        media_type: Keyword.get(opts, :media_type, "application/yaml"),
        source_artifact: Keyword.get(opts, :source_artifact, sample_yaml_source()),
        uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
        metadata: Keyword.get(opts, :metadata, %{})
      })

    assert {:ok, persisted} = Catalog.persist_artifact(mission.organization_id, artifact)
    persisted
  end

  @spec persist_catalog_import_run!(Artifact.t(), keyword()) :: ImportRun.t()
  def persist_catalog_import_run!(%Artifact{} = artifact, opts \\ []) do
    assert {:ok, run} =
             Catalog.start_import_run(
               artifact.organization_id,
               artifact.mission_id,
               artifact.artifact_id,
               Keyword.get(opts, :importer_key, "cadence_yaml"),
               requested_by: Keyword.get(opts, :requested_by, %{}),
               catalog_database_id:
                 Keyword.get(opts, :catalog_database_id, artifact.catalog_database_id),
               metadata: Keyword.get(opts, :metadata, %{})
             )

    run
  end

  @spec start_catalog_revision_import!(CatalogDatabase.t(), keyword()) :: ImportRun.t()
  def start_catalog_revision_import!(%CatalogDatabase{} = database, opts \\ []) do
    artifact =
      Artifact.new(%{
        mission_id: database.mission_id,
        catalog_database_id: database.catalog_database_id,
        catalog_family: Keyword.get(opts, :catalog_family, database.catalog_family),
        artifact_name: Keyword.get(opts, :artifact_name, "mission.yaml"),
        format_key:
          Keyword.get(opts, :format_key, database.default_importer_key || "cadence_yaml"),
        media_type: Keyword.get(opts, :media_type, "application/yaml"),
        source_artifact: Keyword.get(opts, :source_artifact, sample_yaml_source()),
        uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
        metadata: Keyword.get(opts, :artifact_metadata, %{})
      })

    assert {:ok, run} =
             Catalog.start_revision_import(
               database.organization_id,
               database.mission_id,
               database.catalog_database_id,
               artifact,
               Keyword.get(opts, :importer_key, database.default_importer_key || "cadence_yaml"),
               requested_by: Keyword.get(opts, :requested_by, %{}),
               metadata: %{
                 "revision_label" => Keyword.get(opts, :revision_label, "Revision 1"),
                 "revision_notes" => Keyword.get(opts, :revision_notes, "")
               }
             )

    run
  end

  @spec complete_catalog_import_run!(ImportRun.t()) :: ImportRun.t()
  def complete_catalog_import_run!(%ImportRun{} = run) do
    assert {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)
    completed
  end

  @spec fetch_catalog_revision_for_run!(ImportRun.t()) :: CatalogRevision.t()
  def fetch_catalog_revision_for_run!(%ImportRun{} = run) do
    assert {:ok, revision} =
             Catalog.fetch_revision_by_import_run(
               run.organization_id,
               run.mission_id,
               run.import_run_id
             )

    revision
  end

  defp sample_yaml_source do
    """
    packets:
      - name: HEALTH
        items:
          - name: mode
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """
  end

  defp widget_specs_to_placements(widget_specs) do
    Enum.map(widget_specs, &widget_spec_to_placement!/1)
  end

  defp widget_spec_to_placement!(%{} = widget_spec) do
    binding = Map.get(widget_spec, :binding, Map.get(widget_spec, "binding", %{}))
    type = widget_spec |> widget_attr(:type) |> to_string()
    mode = binding |> widget_attr(:mode) |> default_widget_mode(type)
    selected_points = selected_widget_points(binding)

    params = %{
      "type" => type,
      "title" => widget_attr(widget_spec, :title),
      "mode" => to_string(mode),
      "spacecraft_id" => widget_attr(binding, :spacecraft_id) || "",
      "binding_source" => widget_attr(binding, :source) || "telemetry",
      "precision" => option_value(widget_spec, :precision, "2"),
      "window_seconds" => option_value(widget_spec, :window_seconds, "300")
    }

    assert {:ok, placement} =
             PlacementEditor.build_placement(params, selected_points, :add_widget)

    case widget_attr(widget_spec, :layout) do
      layout when is_map(layout) -> %Placement{placement | layout: layout}
      _missing -> placement
    end
  end

  defp normalize_dashboard_placement!(%Placement{} = placement), do: placement

  defp normalize_dashboard_placement!(%{} = widget_spec),
    do: widget_spec_to_placement!(widget_spec)

  defp widget_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp default_widget_mode(nil, "constellation_health"), do: :constellation
  defp default_widget_mode(nil, _type), do: :context
  defp default_widget_mode(mode, _type), do: mode

  defp selected_widget_points(binding) do
    widget_attr(binding, :point_ids) ||
      widget_attr(binding, :observables) ||
      widget_attr(binding, :point_id)
  end

  defp option_value(widget_spec, key, default) do
    options = widget_attr(widget_spec, :options) || %{}

    options
    |> widget_attr(key)
    |> case do
      nil -> default
      value -> to_string(value)
    end
  end
end
