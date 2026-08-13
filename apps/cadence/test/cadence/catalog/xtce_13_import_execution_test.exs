defmodule Cadence.Catalog.Xtce13ImportExecutionTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Importers.Xtce13
  alias Cadence.Catalog.{ImportExecution, Source}

  test "persists an XTCE declaration layer, resolved revision, and all target plans" do
    organization_id = "org-xtce-execution"
    mission_id = "mission-xtce-execution"
    import_run_id = "import-xtce-execution"
    persist_mission_scope(organization_id, mission_id)

    source =
      Source.new(%{
        artifact_id: "artifact-xtce-execution",
        organization_id: organization_id,
        mission_id: mission_id,
        catalog_family: :combined,
        artifact_name: "vehicle.xtce",
        format_key: "xtce_1_3",
        format_version: "1.3",
        media_type: "application/xtce+xml",
        source_artifact: """
        <?xml version="1.0" encoding="UTF-8"?>
        <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Vehicle">
          <TelemetryMetaData>
            <ParameterTypeSet>
              <IntegerParameterType name="CounterType">
                <IntegerDataEncoding sizeInBits="16" encoding="unsigned"/>
              </IntegerParameterType>
            </ParameterTypeSet>
            <ParameterSet>
              <Parameter name="counter" parameterTypeRef="CounterType"/>
            </ParameterSet>
          </TelemetryMetaData>
        </SpaceSystem>
        """
      })

    assert {:ok, import_result} = Xtce13.import(source, %{import_run_id: import_run_id})
    assert {:ok, outcome} = ImportExecution.persist(organization_id, import_run_id, import_result)

    assert outcome.snapshot_id == nil
    assert outcome.result_document["mission_model"]["declaration_count"] == 4
    assert map_size(outcome.result_document["mission_model"]["plans"]) == 4

    revision_id = outcome.result_document["mission_model"]["revision_id"]

    assert {:ok, revision} =
             Cadence.MissionModels.fetch_revision(organization_id, mission_id, revision_id)

    assert revision.layer_ids == outcome.result_document["mission_model"]["layer_ids"]

    assert {:ok, plans} =
             Cadence.MissionModels.fetch_runtime_plans(organization_id, mission_id, revision_id)

    assert Enum.all?(plans, fn {_target, plan} -> plan.status == :ready end)
  end
end
