defmodule CadenceWeb.Console.CatalogTwoReadsAPITest do
  @moduledoc """
  #195 and #146's read fields over HTTP.

  - The revision read's `catalog_revision` carries `import_run_id`, `breaking` and `breaking_base`
    (ux U102): a database's first revision has no base, and a later one counts what the import
    page's C3 diff counted for its run.
  - Import runs carry `requested_by` (ux U103, mms-security 11-19): a person is named only while
    they're an active member of the mission's organization, a service only when it belongs to it,
    and Cadence by its stored system name. No email or id is ever sent.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Catalog.Actor
  alias Cadence.Reads.Catalog.RevisionBase
  alias Cadence.Repo
  alias Cadence.TestSupport.CatalogTestActor
  alias CadenceWeb.TestFixtures

  @second_yaml """
  packets:
    - name: HEALTH
      items:
        - name: temp
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands: []
  """

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ana R.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    database = TestFixtures.persist_catalog_database!(mission)

    %{
      org: org,
      admin: admin,
      mission: mission,
      database: database,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_data(c, path),
    do:
      c.admin
      |> TestFixtures.member_conn()
      |> get(c.base <> path)
      |> json_response(200)
      |> Map.fetch!("data")

  defp import!(c, opts),
    do:
      c.database
      |> TestFixtures.start_catalog_revision_import!(opts)
      |> TestFixtures.complete_catalog_import_run!()

  defp revision_read(c, run) do
    model = TestFixtures.fetch_catalog_revision_for_run!(run).mission_model_revision_id
    get_data(c, "/mission-model-revisions/#{model}")["catalog_revision"]
  end

  describe "#195: the revision read's breaking count" do
    test "a first revision has no base; a later one counts what its import's C3 diff did", c do
      first = import!(c, revision_label: "FSW 1")
      first_revision = TestFixtures.fetch_catalog_revision_for_run!(first)

      assert %{
               "number" => 1,
               "import_run_id" => first_run_id,
               "breaking" => nil,
               "breaking_base" => nil
             } = revision_read(c, first)

      assert first_run_id == first.import_run_id

      second = import!(c, revision_label: "FSW 2", source_artifact: @second_yaml)
      read = revision_read(c, second)
      c3 = get_data(c, "/catalog/imports/#{second.import_run_id}")

      assert read["number"] == 2
      assert read["import_run_id"] == second.import_run_id

      assert read["breaking_base"] == %{
               "catalog_revision_id" => first_revision.catalog_revision_id,
               "revision" => 1
             }

      # Removing `mode` breaks; the count is the import page's, from the same base.
      assert c3["base_revision"]["id"] == first_revision.catalog_revision_id
      assert read["breaking"] == c3["diff"]["summary"]["breaking"]
      assert read["breaking"] > 0

      # A later import doesn't move the first revision's base.
      assert %{"breaking" => nil, "breaking_base" => nil} = revision_read(c, first)
    end

    test "with a base but no readable diff, breaking is null, never 0", c do
      first =
        c |> import!(revision_label: "FSW 1") |> TestFixtures.fetch_catalog_revision_for_run!()

      unreadable = %{first | revision_number: 2, mission_model_revision_id: nil}

      assert RevisionBase.breaking(c.org.organization_id, c.mission.mission_id, unreadable) == %{
               breaking: nil,
               breaking_base: %{catalog_revision_id: first.catalog_revision_id, revision: 1}
             }
    end
  end

  describe "#146: requested_by on import runs" do
    setup c do
      other_org = TestFixtures.persist_org!()

      member = TestFixtures.persist_user!(display_name: "Mira K.")
      TestFixtures.grant_membership!(member, c.org)

      outsider = TestFixtures.persist_user!(display_name: "Support Admin")
      TestFixtures.grant_membership!(outsider, other_org)

      former = TestFixtures.persist_user!(display_name: "Former Member")
      TestFixtures.grant_membership!(former, c.org)

      from(m in OrganizationMembershipRow,
        where: m.user_id == ^former.user_id and m.organization_id == ^c.org.organization_id
      )
      |> Repo.update_all(set: [lifecycle_state: "revoked"])

      unnamed = TestFixtures.persist_user!(display_name: "Unnamed")
      TestFixtures.grant_membership!(unnamed, c.org)

      from(u in UserRow, where: u.user_id == ^unnamed.user_id)
      |> Repo.update_all(set: [display_name: ""])

      own_service = service!(c.org, "Nightly planner")
      foreign_service = service!(other_org, "Other org's bot")

      runs =
        for {key, actor} <- [
              member: user_actor(member),
              outsider: user_actor(outsider),
              former: user_actor(former),
              unnamed: user_actor(unnamed),
              own_service: service_actor(own_service),
              foreign_service: service_actor(foreign_service),
              system: CatalogTestActor.system(),
              # #513 (ux on #516): a seed run by a member reads 'by Cadence, run by Mira K.'.
              seed_by_member: Actor.system("seed:test", "Test seed", member.user_id)
            ],
            into: %{} do
          run =
            TestFixtures.start_catalog_revision_import!(c.database,
              requested_by: actor,
              revision_label: "by #{key}"
            )

          {run.import_run_id, key}
        end

      %{runs: runs, emails: [member, outsider, former, unnamed] |> Enum.map(& &1.email)}
    end

    @expected %{
      member: %{"kind" => "user", "name" => "Mira K.", "run_by" => nil},
      outsider: %{"kind" => "user", "name" => nil, "run_by" => nil},
      former: %{"kind" => "user", "name" => nil, "run_by" => nil},
      unnamed: %{"kind" => "user", "name" => nil, "run_by" => nil},
      own_service: %{"kind" => "service", "name" => "Nightly planner", "run_by" => nil},
      foreign_service: %{"kind" => "service", "name" => nil, "run_by" => nil},
      # The fixture's runner isn't a member, so it's run by someone not named (#513).
      system: %{
        "kind" => "system",
        "name" => "Cadence test fixture",
        "run_by" => %{"name" => nil}
      },
      seed_by_member: %{
        "kind" => "system",
        "name" => "Test seed",
        "run_by" => %{"name" => "Mira K."}
      }
    }

    test "C1's runs name members, own services and Cadence; never an outsider, email or id", c do
      rows = get_data(c, "/catalog")["database"]["import_runs"]
      assert length(rows) == map_size(c.runs)

      for row <- rows do
        key = Map.fetch!(c.runs, row["id"])
        assert row["requested_by"] == Map.fetch!(@expected, key), "#{key}"
      end

      encoded = Jason.encode!(rows)
      for email <- c.emails, do: refute(encoded =~ email)
      refute encoded =~ "Stored name"
    end

    test "C3's run detail and the source-file page carry the same requested_by", c do
      for {run_id, key} <- c.runs do
        detail = get_data(c, "/catalog/imports/#{run_id}")
        assert detail["requested_by"] == Map.fetch!(@expected, key), "#{key}"

        artifact_id = detail["file"]["artifact"]["id"]
        [row] = get_data(c, "/catalog/artifacts/#{artifact_id}")["import_runs"]
        assert row["requested_by"] == Map.fetch!(@expected, key), "#{key}"
      end
    end
  end

  # #474's named_actors/2 (mms-engineer's ask, landed in #471): C1's revisions[].actor follows the
  # same rule as requested_by, never the stored name or email.
  test "C1's revisions[].actor names a member and no one else, never by email", c do
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(member, c.org)
    outsider = TestFixtures.persist_user!(display_name: "Support Admin")
    TestFixtures.grant_membership!(outsider, TestFixtures.persist_org!())

    import!(c, revision_label: "by member", requested_by: user_actor(member))

    import!(c,
      revision_label: "by outsider",
      requested_by: user_actor(outsider),
      source_artifact: @second_yaml
    )

    revisions = get_data(c, "/catalog")["database"]["revisions"]
    by_label = Map.new(revisions, &{&1["label"], &1["actor"]})

    assert by_label["by member"] == %{"kind" => "user", "name" => "Mira K.", "run_by" => nil}
    assert by_label["by outsider"] == %{"kind" => "user", "name" => nil, "run_by" => nil}

    encoded = Jason.encode!(revisions)
    for email <- [member.email, outsider.email], do: refute(encoded =~ email)
    refute encoded =~ "Stored name"
  end

  # The stored actor's own name and email are what Catalog.Actor records at import; the read uses
  # neither (a person's name is looked up live, under the mission's organization).
  defp user_actor(user),
    do: %{
      "actor_kind" => "user",
      "user_id" => user.user_id,
      "name" => "Stored name",
      "email" => user.email
    }

  defp service_actor(service),
    do: %{
      "actor_kind" => "service",
      "service_identity_id" => service.service_identity_id,
      "name" => "Stored name"
    }

  defp service!(org, name) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-#{System.unique_integer([:positive])}",
        organization_id: org.organization_id,
        display_name: name,
        capabilities: [:organization_admin]
      })

    # #280: issuing records who issued it (a person of the same organization).
    issuer = %Cadence.Auth.Scope{
      actor_kind: :user,
      organization_id: org.organization_id,
      user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
    }

    assert {:ok, %{service_identity: service}} =
             Cadence.Auth.issue_service_identity(identity, issuer)

    service
  end
end
