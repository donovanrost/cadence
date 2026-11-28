defmodule Cadence.DevProfileTest do
  use Cadence.UnitCase, async: true

  alias Cadence.DevProfile

  test "loads the bundled demo profile by name" do
    assert {:ok, profile} = DevProfile.load("demo_spacecraft")

    assert profile.name == "demo_spacecraft"
    assert String.ends_with?(profile.path, "dev/profiles/demo_spacecraft.yaml")

    bootstrap = DevProfile.bootstrap_config(profile)
    profiler = DevProfile.profiler_defaults(profile)

    assert bootstrap["mission_id"] == "mission-alpha"
    assert bootstrap["base_url"] == "http://127.0.0.1:4001"

    assert String.ends_with?(
             bootstrap["definitions_path"],
             "/dev/catalogs/demo_spacecraft.yaml"
           )

    assert profiler.node == "cadence"
    assert profiler.mission_id == "mission-alpha"
  end

  @tag :tmp_dir
  test "loads an explicit profile path and falls back to simulator cadence values", %{
    tmp_dir: tmp_dir
  } do
    path =
      write_profile!(tmp_dir, """
      simulator:
        cadence:
          url: http://127.0.0.1:4101
          organization_id: org-beta
          mission_id: mission-beta
        definitions: priv/databases/custom.yaml
      profiler:
        node: cadence-dev
      """)

    assert {:ok, profile} = DevProfile.load(path)

    bootstrap = DevProfile.bootstrap_config(profile)
    profiler = DevProfile.profiler_defaults(profile)

    assert bootstrap["base_url"] == "http://127.0.0.1:4101"
    assert bootstrap["organization_id"] == "org-beta"
    assert bootstrap["mission_id"] == "mission-beta"

    assert bootstrap["definitions_path"] ==
             Path.expand("priv/databases/custom.yaml", Path.dirname(path))

    assert profiler.node == "cadence-dev"
    assert profiler.mission_id == "mission-beta"
  end

  test "returns a helpful error for a missing named profile" do
    assert {:error, message} = DevProfile.load("definitely_missing_profile")
    assert message =~ "could not find dev profile"
    assert message =~ "dev/profiles/definitely_missing_profile.yaml"
  end

  defp write_profile!(tmp_dir, content) do
    path = Path.join(tmp_dir, "profile.yaml")
    File.write!(path, content)
    path
  end
end
