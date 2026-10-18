defmodule CadenceWeb.DashboardSettingsTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    Document,
    DocumentCodec,
    Documents,
    Management,
    SettingsAuthoring,
    SettingsInput,
    SettingsStore
  }

  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Reads.Dashboards.Settings
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)

    {:ok, document} =
      Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "settings-dashboard"
      })

    %{org: org, user: user, scope: scope, mission: mission, document: document}
  end

  test "settings read projections receive domain values inside the storage-owned read transaction",
       c do
    assert {:ok, snapshot} =
             SettingsStore.with_settings_snapshot(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               fn snapshot ->
                 assert Repo.in_transaction?()
                 refute is_struct(snapshot)
                 refute Map.has_key?(snapshot, :__meta__)
                 assert %Document{} = snapshot.document
                 assert snapshot.document.dashboard_id == snapshot.dashboard_id
                 assert Document.version(snapshot.document) == snapshot.latest_version
                 snapshot
               end
             )

    model = read(c)
    assert model.document_version == snapshot.latest_version
    assert model.revision == snapshot.lock_version
    assert model.lifecycle == snapshot.lifecycle_state

    assert {:error, :unavailable} =
             SettingsStore.with_settings_snapshot(
               c.org.organization_id,
               "foreign",
               c.document.dashboard_id,
               fn _ -> flunk("foreign snapshot") end
             )
  end

  test "persisted settings saves retain publication, widgets and metadata with actor attribution",
       c do
    {:ok, _} =
      Documents.publish(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        1,
        []
      )

    before = read(c)
    assert {:ok, receipt} = execute(c, "save_settings", save_fields())
    assert receipt.document_version == 2
    assert receipt.revision == before.revision + 1
    after_save = read(c)
    assert after_save.name == "Power settings"
    assert after_save.description == "Updated description"
    assert after_save.tags == ["power", "ops"]
    assert Jason.decode!(after_save.defaults_json) == %{"extension" => %{"retained" => true}}
    assert after_save.published_version == 1

    {:ok, saved} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    assert saved.placements == c.document.placements
    assert saved.sections == c.document.sections

    {:ok, version} =
      Documents.fetch_version(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        2
      )

    assert version.created_by == c.user.user_id

    {:ok, published} =
      Documents.fetch_published(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )

    assert published.name == c.document.name
  end

  test "all commands require exact bounded inputs and observed revisions", c do
    assert {:error, :invalid_input} =
             execute(c, "save_settings", Map.put(save_fields(), "created_by", "forged"))

    for fields <- [
          Map.put(save_fields(), "tags", ["duplicate", "duplicate"]),
          Map.put(save_fields(), "defaults_json", "[]"),
          Map.put(save_fields(), "defaults_json", String.duplicate(" ", 32_769)),
          Map.put(save_fields(), "name", " "),
          Map.put(save_fields(), "description", String.duplicate("x", 501))
        ] do
      assert {:error, :invalid_input} = execute(c, "save_settings", fields)
    end

    for hours <- ["", "24", 0, -1, 1.5, 8761] do
      assert {:error, :invalid_input} = execute(c, "create_share", share_fields(hours))
    end

    assert {:error, :invalid_input} =
             execute(c, "create_snapshot", %{"data_visibility" => "public"})

    assert {:error, :invalid_input} =
             execute(c, "archive_dashboard", %{"dashboard_id" => "forged"})

    assert {:error, :invalid_input} =
             SettingsInput.admit("archive_dashboard", %{"expected_version" => 1})

    assert {:error, :conflict} =
             execute(c, "save_settings", Map.put(save_fields(), "expected_revision", 999))

    assert read(c).document_version == 1
    assert read(c).shares.rows == []
  end

  test "shares preserve expiration and revocation is bound to the selected dashboard", c do
    assert {:ok, first} = execute(c, "create_share", share_fields(nil))
    assert {:ok, expiring} = execute(c, "create_share", share_fields(24))

    {:ok, share} =
      Management.fetch_active_share(
        c.org.organization_id,
        c.mission.mission_id,
        first.resource_id
      )

    assert share.created_by == c.user.user_id
    assert share.expires_at == nil
    assert share.access_policy == "mission_member"
    assert share.runtime_context == %{}

    {:ok, timed} =
      Management.fetch_active_share(
        c.org.organization_id,
        c.mission.mission_id,
        expiring.resource_id
      )

    assert DateTime.diff(timed.expires_at, timed.inserted_at) in 86_399..86_400

    {:ok, other} =
      Documents.persist(c.org.organization_id, %{c.document | dashboard_id: "other-dashboard"})

    foreign_context = %{c | document: other}

    assert {:error, :unavailable} =
             execute(foreign_context, "revoke_share", %{"share_id" => first.resource_id})

    assert {:ok, _} = execute(c, "revoke_share", %{"share_id" => first.resource_id})
    assert {:error, :conflict} = execute(c, "revoke_share", %{"share_id" => first.resource_id})
    assert Enum.find(read(c).shares.rows, &(&1.id == first.resource_id)).state == "revoked"
  end

  test "snapshot captures the observed draft immutably and never publishes it", c do
    assert {:ok, receipt} =
             execute(c, "create_snapshot", %{"data_visibility" => "definition_only"})

    assert {:ok, _} = execute(c, "save_settings", save_fields())

    {:ok, snapshot} =
      Management.fetch_snapshot(c.org.organization_id, c.mission.mission_id, receipt.resource_id)

    assert snapshot.dashboard_version == 1
    assert snapshot.created_by == c.user.user_id
    assert snapshot.document["name"] == c.document.name
    assert snapshot.data_semantics == "definition_at_version_current_data"
    assert snapshot.data_visibility == "definition_only"
    model = read(c)
    assert model.published_version == nil
    assert [%{document_version: 1}] = model.snapshots.rows
    refute Map.has_key?(hd(model.snapshots.rows), :document)
    refute Map.has_key?(hd(model.snapshots.rows), :runtime_context)
  end

  test "publication-only changes invalidate settings and lifecycle preconditions", c do
    observed = read(c)

    {:ok, _} =
      Documents.publish(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        1,
        []
      )

    assert read(c).document_version == observed.document_version

    for {event, fields} <- [
          {"save_settings", save_fields()},
          {"archive_dashboard", %{}},
          {"create_share", share_fields(nil)},
          {"create_snapshot", %{"data_visibility" => "definition_only"}}
        ] do
      command =
        Map.merge(fields, %{
          "expected_version" => observed.document_version,
          "expected_revision" => observed.revision
        })

      assert {:error, :conflict} =
               SettingsAuthoring.execute(
                 c.scope,
                 c.mission.mission_id,
                 c.document.dashboard_id,
                 event,
                 command
               )
    end

    # The document store also enforces this if publication occurs after the authoring read.
    opts = [expected_version: observed.document_version, expected_revision: observed.revision]

    assert {:error, :dashboard_revision_conflict} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               c.document,
               opts
             )

    assert {:error, :dashboard_revision_conflict} =
             Documents.archive(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               opts
             )

    assert read(c).lifecycle == "active"
  end

  test "archiving retains readable metadata and rejects further authoring", c do
    before = read(c)
    assert {:ok, receipt} = execute(c, "archive_dashboard", %{})
    assert receipt.revision == before.revision + 1
    assert receipt.document_version == before.document_version
    assert read(c).lifecycle == "archived"
    assert {:error, :unavailable} = execute(c, "create_share", share_fields(nil))
    assert {:error, :unavailable} = execute(c, "save_settings", save_fields())
  end

  test "read and effect admission reject foreign mission scopes and malformed queries", c do
    scope = %{c.scope | mission_id: "foreign-mission"}

    assert {:error, :unavailable} =
             Settings.load(scope, c.mission.mission_id, c.document.dashboard_id)

    assert {:error, :forbidden} =
             SettingsAuthoring.execute(
               scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               "archive_dashboard",
               %{}
             )

    assert {:error, :unavailable} =
             Settings.load(c.scope, "foreign-mission", c.document.dashboard_id)

    for params <- [
          %{"dashboard_id" => "forged"},
          %{"after_share" => 1},
          %{"after_snapshot" => String.duplicate("x", 257)}
        ] do
      assert {:error, :unavailable} =
               Settings.load(c.scope, c.mission.mission_id, c.document.dashboard_id, params)
    end

    assert Repo.get!(DashboardRow, c.document.dashboard_id).lifecycle_state == "active"
    assert Document.version(c.document) == 1
  end

  test "bounded metadata pages round-trip through the real frontend consumer", c do
    empty = read(c)

    populate_metadata(c)

    {:ok, other} =
      Documents.persist(c.org.organization_id, %{c.document | dashboard_id: "other-dashboard"})

    {:ok, foreign_share} =
      Management.create_share(
        c.org.organization_id,
        c.mission.mission_id,
        other.dashboard_id,
        %{}
      )

    first = read(c)

    for collection <- [first.shares, first.snapshots, first.deployments] do
      assert length(collection.rows) == 25
      assert collection.next == List.last(collection.rows).id
    end

    second =
      read(c, %{
        "after_share" => first.shares.next,
        "after_snapshot" => first.snapshots.next,
        "after_deployment" => first.deployments.next
      })

    for collection <- [second.shares, second.snapshots, second.deployments] do
      assert length(collection.rows) == 1
      assert collection.next == nil
    end

    ids = Enum.map(first.shares.rows ++ second.shares.rows, & &1.id)
    assert length(Enum.uniq(ids)) == 26
    refute foreign_share.dashboard_share_id in ids
    refute Enum.any?(first.shares.rows, &Map.has_key?(&1, :runtime_context))

    expired = Repo.get!(Cadence.Dashboards.DashboardShare, hd(first.shares.rows).id)

    expired
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()

    expired_page = read(c)

    assert Enum.find(expired_page.shares.rows, &(&1.id == expired.dashboard_share_id)).state ==
             "expired"

    assert {:ok, _} = execute(c, "archive_dashboard", %{})
    archived = read(c)

    renderer =
      Path.expand(
        "../../../../frontend/modules/dashboards-and-exploration/src/features/settings/producer-contract-check.mjs",
        __DIR__
      )

    node =
      System.find_executable("node") || flunk("Node is required for settings producer contracts")

    {output, status} =
      System.cmd(
        node,
        [
          "--no-warnings",
          renderer,
          Jason.encode!([empty, first, second, expired_page, archived])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "oversized deployment metadata is unavailable rather than an unbounded payload", c do
    {:ok, _} =
      Management.record_deployment(
        c.org.organization_id,
        c.mission.mission_id,
        c.document,
        "artifact",
        String.duplicate("x", 121)
      )

    assert {:error, :unavailable} =
             Settings.load(c.scope, c.mission.mission_id, c.document.dashboard_id)
  end

  test "legacy document migration cannot silently replace the version a command observed", c do
    row = Repo.get!(DashboardRow, c.document.dashboard_id)

    row
    |> Ecto.Changeset.change(document: Map.delete(row.document, "schema_version"))
    |> Repo.update!()

    command =
      Map.merge(share_fields(nil), %{
        "expected_version" => 1,
        "expected_revision" => row.lock_version
      })

    assert {:error, :conflict} =
             SettingsAuthoring.execute(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               "create_share",
               command
             )

    model = read(c)
    assert model.document_version == 2
    assert model.revision == row.lock_version + 1
    assert model.shares.rows == []
    assert {:ok, _} = execute(c, "create_share", share_fields(nil))
  end

  defp populate_metadata(c) do
    for i <- 1..26 do
      {:ok, _} =
        Management.create_share(
          c.org.organization_id,
          c.mission.mission_id,
          c.document.dashboard_id,
          %{"selected_id" => "private-context-#{i}"}
        )

      {:ok, _} =
        Management.create_snapshot(
          c.org.organization_id,
          c.mission.mission_id,
          c.document,
          %{},
          []
        )

      {:ok, _} =
        Management.record_deployment(
          c.org.organization_id,
          c.mission.mission_id,
          c.document,
          "artifact-#{i}",
          "flight"
        )
    end
  end

  defp read(c, params \\ %{}) do
    {:ok, model} = Settings.load(c.scope, c.mission.mission_id, c.document.dashboard_id, params)
    model
  end

  defp execute(c, event, fields) do
    model = read(c)

    input =
      Map.merge(
        %{"expected_version" => model.document_version, "expected_revision" => model.revision},
        fields
      )

    SettingsAuthoring.execute(
      c.scope,
      c.mission.mission_id,
      c.document.dashboard_id,
      event,
      input
    )
  end

  defp save_fields,
    do: %{
      "name" => "Power settings",
      "description" => "Updated description",
      "tags" => ["power", "ops"],
      "defaults_json" => ~s({"extension":{"retained":true}})
    }

  defp share_fields(hours),
    do: %{"data_visibility" => "authorized_runtime_data", "expires_in_hours" => hours}
end
