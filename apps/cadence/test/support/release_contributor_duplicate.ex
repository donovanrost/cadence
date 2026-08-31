defmodule Cadence.TestReleaseContributors.Duplicate do
  @moduledoc false

  alias Cadence.Applications.ReleaseContribution

  def release_contributions do
    contribution = %ReleaseContribution{
      application_key: "synthetic_release",
      application_version: 1,
      surface_id: "overview",
      surface_version: 1,
      federation: :module_federation,
      release_id: "synthetic-release-v1",
      remote_name: "synthetic_release",
      manifest_path: "/assets/synthetic/release-manifest.json",
      exposed_module: "./Application"
    }

    [contribution, contribution]
  end
end
