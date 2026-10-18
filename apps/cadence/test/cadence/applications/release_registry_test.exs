defmodule Cadence.Applications.ReleaseRegistryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.{ReleaseContribution, ReleaseRegistry}

  test "keeps the compiled release registry valid" do
    assert :ok = ReleaseRegistry.validate()
    assert Enum.all?(ReleaseRegistry.all(), &(ReleaseContribution.validate(&1) == :ok))
  end

  test "fails closed for raising, throwing, exiting, malformed, duplicate, and invalid contributors" do
    contributors = [
      Cadence.TestReleaseContributors.Raising,
      Cadence.TestReleaseContributors.Throwing,
      Cadence.TestReleaseContributors.Exiting,
      Cadence.TestReleaseContributors.Malformed,
      Cadence.TestReleaseContributors.NonList,
      Cadence.TestReleaseContributors.Duplicate,
      Cadence.TestReleaseContributors.InvalidIdentity
    ]

    for contributor <- contributors do
      assert ReleaseRegistry.all([contributor]) == []

      assert {:error, :invalid_release_contribution_registry} =
               ReleaseRegistry.validate([contributor])
    end
  end
end
