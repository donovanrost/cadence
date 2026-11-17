defmodule Cadence.Catalog.ActorTest do
  # lead 11-17 (import actor, a + b + c): an import names who ran it, the catalog read names it
  # whichever path recorded it, and no path can store an empty importer again.
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.{Actor, Artifact}
  alias Cadence.Reads.CatalogOverview

  setup do
    id = Integer.to_string(System.unique_integer([:positive]))
    org = "org-catalog-actor-" <> id
    mission = "mission-catalog-actor-" <> id
    persist_mission_scope(org, mission)
    %{org: org, mission: mission}
  end

  test "people, services and Cadence itself, never with a bare id" do
    user = %Scope{
      actor_kind: :user,
      user: User.new(%{user_id: "u-1", email: "u@example.test", display_name: "Una"})
    }

    service = %Scope{
      actor_kind: :service,
      service_identity: %{service_identity_id: "svc-1", display_name: "Pipeline"}
    }

    assert {:ok,
            %{
              "actor_kind" => "user",
              "user_id" => "u-1",
              "name" => "Una",
              "email" => "u@example.test"
            }} = Actor.from_scope(user)

    assert {:ok,
            %{"actor_kind" => "service", "service_identity_id" => "svc-1", "name" => "Pipeline"}} =
             Actor.from_scope(service)

    assert %{"actor_kind" => "system", "system_id" => "seed:x", "name" => "X seed"} =
             system = Actor.system("seed:x", "X seed")

    for {:ok, actor} <- [Actor.from_scope(user), Actor.from_scope(service), {:ok, system}],
        do: refute(Map.has_key?(actor, "id"))

    assert {:error, :catalog_import_actor_required} = Actor.from_scope(%Scope{actor_kind: :user})
  end

  test "an import that names no one is refused before anything is stored", ctx do
    {:ok, database} =
      Catalog.create_database(ctx.org, ctx.mission, %{
        name: "Bus",
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    artifact = artifact(ctx, database.catalog_database_id, %{})

    for requested_by <- [nil, %{}, %{"actor_kind" => "user"}, %{"id" => "someone"}] do
      opts = if requested_by, do: [requested_by: requested_by], else: []

      assert {:error, :catalog_import_actor_required} =
               Catalog.start_revision_import(
                 ctx.org,
                 ctx.mission,
                 database.catalog_database_id,
                 artifact,
                 "cadence_yaml",
                 opts
               )
    end

    assert Catalog.list_artifacts(ctx.org, ctx.mission) == []

    {:ok, persisted} = Catalog.persist_artifact(ctx.org, artifact)

    assert {:error, :catalog_import_actor_required} =
             Catalog.start_import_run(ctx.org, ctx.mission, persisted.artifact_id, "cadence_yaml")

    assert Catalog.list_import_runs(ctx.org, ctx.mission) == []
  end

  test "the catalog read names an actor the REST API recorded", ctx do
    rest_user = %{"actor_kind" => "user", "user_id" => "u-2", "user_email" => "rest@example.test"}

    rest_service = %{
      "actor_kind" => "service",
      "service_identity_id" => "svc-2",
      "service_identity_display_name" => "Uploader"
    }

    for {uploaded_by, name} <- [
          {rest_user, "rest@example.test"},
          {rest_service, "Uploader"},
          {%{"user_display_name" => "", "user_email" => "e@example.test"}, "e@example.test"}
        ] do
      {:ok, artifact} = Catalog.persist_artifact(ctx.org, artifact(ctx, nil, uploaded_by))

      assert {:ok, %{artifact: %{uploaded_by: %{name: ^name}}}} =
               CatalogOverview.artifact(ctx.org, ctx.mission, artifact.artifact_id)
    end

    {:ok, artifact} = Catalog.persist_artifact(ctx.org, artifact(ctx, nil, %{}))

    assert {:ok, %{artifact: %{uploaded_by: nil}}} =
             CatalogOverview.artifact(ctx.org, ctx.mission, artifact.artifact_id)
  end

  defp artifact(ctx, database_id, uploaded_by) do
    Artifact.new(%{
      mission_id: ctx.mission,
      catalog_database_id: database_id,
      catalog_family: :combined,
      artifact_name: "bus-#{System.unique_integer([:positive])}.yaml",
      format_key: "cadence_yaml",
      media_type: "application/yaml",
      source_artifact: "packets: []\ncommands: []\n",
      uploaded_by: uploaded_by
    })
  end
end
