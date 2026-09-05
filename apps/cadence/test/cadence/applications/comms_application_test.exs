defmodule Cadence.Applications.CommsApplicationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.{ApplicationDefinition, Comms, ReleaseContribution}

  test "publishes the complete mission-scoped Comms surface contract" do
    assert Comms.identity() == %{
             application_key: "comms",
             application_version: 1,
             package_id: "cadence.comms",
             package_version: 1,
             surface_version: 1,
             release_id: "comms-v1",
             remote_name: "cadence_comms",
             manifest_path: "/assets/application-host/comms/mf-manifest.json",
             exposed_module: "./Application"
           }

    assert ApplicationDefinition.validate(Comms.definition()) == :ok

    assert Comms.surface_ids() == [
             "overview",
             "validation",
             "transports",
             "transport",
             "routing",
             "routing_detail",
             "ground_stations",
             "ground_station"
           ]

    assert Enum.map(Comms.surface_query_contributions(), & &1.query_id) == [
             "cadence.comms.overview",
             "cadence.comms.validation",
             "cadence.comms.transports",
             "cadence.comms.transport",
             "cadence.comms.routing",
             "cadence.comms.routing_detail",
             "cadence.comms.ground_stations",
             "cadence.comms.ground_station"
           ]
  end

  test "contributes one immutable module-federation release coordinate per surface" do
    contributions = Comms.release_contributions()

    assert length(contributions) == 8
    assert Enum.all?(contributions, &(ReleaseContribution.validate(&1) == :ok))

    assert Enum.uniq_by(contributions, &ReleaseContribution.release/1) == [
             %ReleaseContribution{
               application_key: "comms",
               application_version: 1,
               surface_id: "overview",
               surface_version: 1,
               federation: :module_federation,
               release_id: "comms-v1",
               remote_name: "cadence_comms",
               manifest_path: "/assets/application-host/comms/mf-manifest.json",
               exposed_module: "./Application"
             }
           ]
  end

  test "leaves the legacy overview identity available as a separate contract" do
    legacy = Cadence.Applications.LegacyCommsOverview.identity()

    assert legacy.application_key == "comms_overview"
    assert legacy.package_id == "cadence.comms_overview"
    assert legacy.query_id == "cadence.comms.overview"
    assert legacy.release_id == "comms-overview-v1"
    assert legacy.remote_name == "cadence_comms_overview"
  end
end
