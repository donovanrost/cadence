defmodule CadenceWeb.ApplicationReleaseRegistryTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.ApplicationReleaseRegistry

  test "keys the checked-in Comms release by application and surface versions" do
    assert {:ok, release} = ApplicationReleaseRegistry.fetch("comms_overview", 1, "overview", 1)

    assert release == %{
             federation: :module_federation,
             release_id: "comms-overview-v1",
             remote_name: "cadence_comms_overview",
             manifest_path: "/assets/application-host/comms-overview/mf-manifest.json",
             exposed_module: "./Application"
           }
  end

  test "does not advertise the unpublished Comms remote" do
    surfaces =
      ~w(overview validation transports transport routing routing_detail ground_stations ground_station)

    Enum.each(surfaces, fn surface_id ->
      assert {:error, :unknown_application_release} =
               ApplicationReleaseRegistry.fetch("comms", 1, surface_id, 1)
    end)

    refute Enum.any?(ApplicationReleaseRegistry.all(), fn {{application_key, _version, _surface,
                                                            _surface_version}, _release} ->
             application_key == "comms"
           end)
  end

  test "advertises the checked-in telemetry packet bindings release coordinate" do
    assert {:ok, release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)

    assert release == %{
             federation: :module_federation,
             release_id: "telemetry-decom-v1",
             remote_name: "cadence_telemetry_decom",
             manifest_path: "/assets/application-host/telemetry-decom/mf-manifest.json",
             exposed_module: "./Application"
           }

    assert Enum.all?(ApplicationReleaseRegistry.all(), fn {_key, release} ->
             String.starts_with?(release.manifest_path, "/assets/") and
               not String.contains?(release.manifest_path, "/releases/current")
           end)
  end
end
