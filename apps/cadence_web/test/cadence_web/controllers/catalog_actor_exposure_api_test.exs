defmodule CadenceWeb.CatalogActorExposureAPITest do
  @moduledoc """
  #366: reads that name who uploaded a catalog file, started an import or imported a model
  revision follow #146's rule (mms-security 11-19). A person is named only while they hold an
  active membership in the mission's organization; a service only when it belongs to it. Nobody's
  email or user id goes out in the stored actor document.

  - The catalog artifact read's `uploaded_by` and the import run read's `requested_by` (`/api/v1`;
    the REST lists went with #748): `{kind, name}`.
  - The model approval read's `imported_by`: `{id, name}`. A member with no display name keeps
    their id with a null name; anyone outside the organization reads both null.
  """
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.ControlPlaneApiFixtures
  import Ecto.Query

  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Reads.MissionModelApprovals
  alias CadenceWeb.TestFixtures

  setup %{conn: conn} do
    %{organization_id: org_id, mission_id: mid} = boot = bootstrap(conn)
    {:ok, org} = Cadence.Organizations.fetch_organization(org_id)
    {:ok, mission} = Cadence.Missions.fetch_mission(org_id, mid)
    other_org = TestFixtures.persist_org!()

    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(member, org)
    unnamed = TestFixtures.persist_user!(display_name: "Unnamed")
    TestFixtures.grant_membership!(unnamed, org)

    Cadence.Repo.update_all(
      from(u in Cadence.Accounts.UserRow, where: u.user_id == ^unnamed.user_id),
      set: [display_name: ""]
    )

    outsider = TestFixtures.persist_user!(display_name: "Support Admin")
    TestFixtures.grant_membership!(outsider, other_org)

    actors = %{
      member: user_actor(member),
      unnamed: user_actor(unnamed),
      outsider: user_actor(outsider),
      own_service: service_actor("svc-bootstrap"),
      foreign_service: service_actor(service!(other_org, "Other org's bot"))
    }

    Map.merge(boot, %{
      org: org,
      mission: mission,
      member: member,
      unnamed: unnamed,
      outsider: outsider,
      actors: actors,
      emails: Enum.map([member, unnamed, outsider], & &1.email),
      hidden_ids: [unnamed.user_id, outsider.user_id]
    })
  end

  @expected %{
    member: %{"kind" => "user", "name" => "Mira K.", "run_by" => nil},
    unnamed: %{"kind" => "user", "name" => nil, "run_by" => nil},
    outsider: %{"kind" => "user", "name" => nil, "run_by" => nil},
    own_service: %{"kind" => "service", "name" => "Control Plane Test Service", "run_by" => nil},
    foreign_service: %{"kind" => "service", "name" => nil, "run_by" => nil}
  }

  test "the artifact and import run reads name only members and own services; no email or id",
       c do
    base = "/api/v1/missions/#{c.mission_id}/catalog"

    shown =
      for {key, actor} <- c.actors do
        artifact =
          TestFixtures.persist_catalog_artifact!(c.mission,
            artifact_name: "#{key}.yaml",
            uploaded_by: actor
          )

        run = TestFixtures.persist_catalog_import_run!(artifact, requested_by: actor)
        shown_artifact = get_data(c, base <> "/artifacts/#{artifact.artifact_id}")["artifact"]
        assert shown_artifact["uploaded_by"] == @expected[key], "#{key}"
        shown_run = get_data(c, base <> "/imports/#{run.import_run_id}")
        assert shown_run["requested_by"] == @expected[key], "#{key}"
        [shown_artifact, shown_run]
      end

    encoded = Jason.encode!(shown)
    for email <- c.emails, do: refute(encoded =~ email)
    for id <- c.hidden_ids, do: refute(encoded =~ id)
    refute encoded =~ "Stored name"
  end

  test "the approval read's imported_by: a member by name, a nameless member by id, an outsider neither",
       c do
    viewer = CatalogFixtures.user_scope(c.organization_id, "viewer")

    for {person, expected} <- [
          {c.member, %{id: c.member.user_id, name: "Mira K."}},
          # A member with no display name keeps their id (membership is the line; api-ops on #487).
          {c.unnamed, %{id: c.unnamed.user_id, name: nil}},
          {c.outsider, %{id: nil, name: nil}}
        ] do
      revision =
        CatalogFixtures.persist_imported_revision!(c.organization_id, c.mission_id,
          approve: false,
          requested_by: user_actor(person)
        )

      model = revision.mission_model_revision_id

      assert {:ok, %{imported_by: ^expected}} =
               MissionModelApprovals.read(viewer, c.mission_id, model)

      listed =
        viewer
        |> MissionModelApprovals.list(c.mission_id, "candidate")
        |> Enum.find(&(&1.id == model))

      assert listed.imported_by == expected
      refute inspect(listed) =~ person.email
    end
  end

  defp get_data(c, path),
    do:
      c.member
      |> TestFixtures.member_conn()
      |> get(path)
      |> json_response(200)
      |> Map.fetch!("data")

  # What Catalog.Actor stores: the read must use neither the stored name nor the email.
  defp user_actor(user),
    do: %{
      "actor_kind" => "user",
      "user_id" => user.user_id,
      "name" => "Stored name",
      "email" => user.email
    }

  defp service_actor(id),
    do: %{
      "actor_kind" => "service",
      "service_identity_id" => id,
      "service_identity_display_name" => "Stored name"
    }

  defp service!(org, name) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-#{System.unique_integer([:positive])}",
        organization_id: org.organization_id,
        display_name: name,
        capabilities: [:organization_admin]
      })

    issuer = %Cadence.Auth.Scope{
      actor_kind: :user,
      organization_id: org.organization_id,
      user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
    }

    {:ok, %{service_identity: service}} = Cadence.Auth.issue_service_identity(identity, issuer)
    service.service_identity_id
  end
end
