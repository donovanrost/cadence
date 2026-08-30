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

  test "does not advertise the standalone telemetry release coordinate" do
    assert {:error, :unknown_application_release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)

    assert Enum.all?(ApplicationReleaseRegistry.all(), fn {_key, release} ->
             String.starts_with?(release.manifest_path, "/assets/") and
               not String.contains?(release.manifest_path, "/releases/current")
           end)
  end
end
