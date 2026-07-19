defmodule Cadence.SharedSchemaBackfillTest do
  use Cadence.DataCase, async: false

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  test "mission-owned inserts inherit organization scope from persisted missions" do
    %{organization: organization, mission: mission} = persist_org_and_mission()

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        mission_id: mission.mission_id,
        display_name: "SC-001"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-001",
        mission_id: mission.mission_id,
        spacecraft_id: "sc-001",
        source_ref: "provider/path-a",
        display_name: "SC-001 Downlink"
      })

    assert {:ok, persisted_source_endpoint} = Cadence.persist_source_endpoint(source_endpoint)

    assert [[organization_id]] =
             query_rows!(
               """
               SELECT organization_id
               FROM mission_source_endpoints
               WHERE source_endpoint_id = $1
               """,
               [persisted_source_endpoint.source_endpoint_id]
             )

    assert organization_id == organization.organization_id
  end

  test "mission-owned rows reject mismatched organization and mission pairings" do
    %{mission: mission} = persist_org_and_mission()

    %{organization: other_organization} =
      persist_org_and_mission(%{
        organization_id: "org-other",
        organization_slug: "other-org",
        organization_name: "Other Org",
        mission_id: "mission-other",
        mission_slug: "other-mission",
        mission_name: "Other Mission"
      })

    inserted_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        """
        INSERT INTO mission_source_endpoints (
          source_endpoint_id,
          mission_id,
          organization_id,
          metadata,
          inserted_at
        )
        VALUES ($1, $2, $3, $4::jsonb, $5)
        """,
        [
          "endpoint-invalid-org",
          mission.mission_id,
          other_organization.organization_id,
          "{}",
          inserted_at
        ]
      )
    end
  end

  defp persist_org_and_mission(attrs \\ %{}) do
    organization =
      Organization.new(%{
        organization_id: Map.get(attrs, :organization_id, "org-alpha"),
        slug: Map.get(attrs, :organization_slug, "alpha-org"),
        display_name: Map.get(attrs, :organization_name, "Alpha Org")
      })

    mission =
      Mission.new(%{
        mission_id: Map.get(attrs, :mission_id, "mission-alpha"),
        organization_id: organization.organization_id,
        slug: Map.get(attrs, :mission_slug, "alpha-mission"),
        display_name: Map.get(attrs, :mission_name, "Alpha Mission")
      })

    assert {:ok, persisted_organization} = Cadence.persist_organization(organization)
    assert {:ok, persisted_mission} = Cadence.Missions.persist_mission(mission)

    %{organization: persisted_organization, mission: persisted_mission}
  end

  defp query_rows!(sql, params) do
    %Postgrex.Result{rows: rows} = Repo.query!(sql, params)
    rows
  end
end
