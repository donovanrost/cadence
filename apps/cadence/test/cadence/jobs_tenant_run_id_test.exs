defmodule Cadence.JobsTenantRunIdTest do
  use ExUnit.Case, async: true

  alias Cadence.Jobs

  test "the same client run id differs across organizations and missions" do
    base = Jobs.tenant_run_id("org-1", "mission-1", "nightly")

    assert "nightly--" <> <<hash::binary-size(10)>> = base
    assert hash =~ ~r/\A[0-9a-f]{10}\z/
    refute Jobs.tenant_run_id("org-2", "mission-1", "nightly") == base
    refute Jobs.tenant_run_id("org-1", "mission-2", "nightly") == base
    # The separator keeps "org-1" + "1mission" apart from "org-11" + "mission".
    refute Jobs.tenant_run_id("org-1", "1mission", "x") ==
             Jobs.tenant_run_id("org-11", "mission", "x")
  end

  test "is stable and never double-applied" do
    once = Jobs.tenant_run_id("org-1", "mission-1", "nightly")

    assert Jobs.tenant_run_id("org-1", "mission-1", "nightly") == once
    assert Jobs.tenant_run_id("org-1", "mission-1", once) == once
    # A request item derived from a namespaced id is recognised too.
    assert Jobs.tenant_run_id("org-1", "mission-1", once <> "-002") == once <> "-002"
  end

  test "another tenant's suffix does not pass for this tenant's" do
    theirs = Jobs.tenant_run_id("org-2", "mission-1", "nightly")
    mine = Jobs.tenant_run_id("org-1", "mission-1", theirs)

    refute mine == theirs
    assert String.starts_with?(mine, theirs <> "--")
  end
end
