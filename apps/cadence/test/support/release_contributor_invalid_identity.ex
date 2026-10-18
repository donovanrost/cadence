defmodule Cadence.TestReleaseContributors.InvalidIdentity do
  @moduledoc false

  alias Cadence.Applications.ReleaseContribution

  def release_contributions do
    [
      %ReleaseContribution{
        application_key: "",
        application_version: 1,
        surface_id: "overview",
        surface_version: 1,
        federation: :module_federation,
        release_id: "synthetic-release-v1",
        remote_name: "synthetic_release",
        manifest_path: "/assets/synthetic/release-manifest.json",
        exposed_module: "./Application"
      }
    ]
  end
end
