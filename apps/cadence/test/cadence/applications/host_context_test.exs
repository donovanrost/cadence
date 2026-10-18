defmodule Cadence.Applications.HostContextTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.HostContext

  test "constructs every tagged scope variant without unrelated identifiers" do
    assert %HostContext{placement: :organization, organization_id: "org-1"} =
             organization = HostContext.organization("org-1")

    assert %HostContext{placement: :user, user_id: "user-1"} = user = HostContext.user("user-1")
    assert %HostContext{placement: :admin} = admin = HostContext.admin()

    assert %HostContext{placement: :mission, mission_id: "mission-1"} =
             mission = HostContext.mission("mission-1")

    assert %HostContext{placement: :spacecraft, mission_id: "mission-1", spacecraft_id: "sc-1"} =
             spacecraft = HostContext.spacecraft("mission-1", "sc-1")

    assert Enum.all?([organization, user, admin, mission, spacecraft], &HostContext.valid?/1)
  end

  test "rejects identifiers belonging to another scope" do
    refute HostContext.valid?(%HostContext{placement: :organization, mission_id: "mission-1"})

    refute HostContext.valid?(%HostContext{
             placement: :user,
             organization_id: "org-1",
             user_id: "user-1"
           })

    refute HostContext.valid?(%HostContext{placement: :admin, mission_id: "mission-1"})
    refute HostContext.valid?(%HostContext{placement: :mission, spacecraft_id: "sc-1"})
    refute HostContext.valid?(%HostContext{placement: :spacecraft, mission_id: "mission-1"})
  end
end
