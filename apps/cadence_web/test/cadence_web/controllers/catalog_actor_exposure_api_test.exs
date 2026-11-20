defmodule CadenceWeb.CatalogActorExposureAPITest do
  @moduledoc """
  #366: reads that name who uploaded a catalog file, started an import or imported a model
  revision follow #146's rule (mms-security 11-19). A person is named only while they hold an
  active membership in the mission's organization; a service only when it belongs to it. Nobody's
  email or user id goes out in the stored actor document.

  - REST `catalog_artifacts[].uploaded_by` and `catalog_import_runs[].requested_by`: `{kind, name}`.
  - The model approval read's `imported_by`: `{id, name}`, both null for anyone not named.
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

  test "REST artifacts and import runs name only members and own services; no email or id", c do
    by_artifact =
      for {key, actor} <- c.actors, into: %{} do
        artifact =
          TestFixtures.persist_catalog_artifact!(c.mission,
            artifact_name: "#{key}.yaml",
            uploaded_by: actor
          )

        run = TestFixtures.persist_catalog_import_run!(artifact, requested_by: actor)
        {artifact.artifact_id, {key, run.import_run_id}}
      end

    base = "/api/organizations/#{c.organization_id}/missions/#{c.mission_id}"
    artifacts = get_data(c, base <> "/catalog_artifacts")
    runs = get_data(c, base <> "/catalog_import_runs")

    for {artifact_id, {key, run_id}} <- by_artifact do
      listed = Enum.find(artifacts, &(&1["artifact_id"] == artifact_id))
      assert listed["uploaded_by"] == @expected[key], "#{key}"
      shown = get_data(c, base <> "/catalog_artifacts/#{artifact_id}")
      assert shown["uploaded_by"] == @expected[key], "#{key}"

      run = Enum.find(runs, &(&1["import_run_id"] == run_id))
      assert run["requested_by"] == @expected[key], "#{key}"
      shown_run = get_data(c, base <> "/catalog_import_runs/#{run_id}")
      assert shown_run["requested_by"] == @expected[key], "#{key}"
    end

    encoded = Jason.encode!([artifacts, runs])
    for email <- c.emails, do: refute(encoded =~ email)
    for id <- c.hidden_ids, do: refute(encoded =~ id)
    refute encoded =~ "Stored name"
  end

  test "the approval read's imported_by names a member, never an outsider or their email", c do
    viewer = CatalogFixtures.user_scope(c.organization_id, "viewer")

    for {person, expected} <- [
          {c.member, %{id: c.member.user_id, name: "Mira K."}},
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
      c.conn
      |> authorize(c.api_token)
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
