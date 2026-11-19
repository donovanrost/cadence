defmodule Cadence.Control.SpacecraftOpsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Control.{Configuration, SpacecraftOps}

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("scops")
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  test "an explicit null switch is refused; absent means unchanged", ctx do
    ops = [
      %{
        kind: "spacecraft",
        action: "create",
        document: %{"display_name" => "A", "telemetry_enabled" => nil}
      },
      %{
        kind: "spacecraft",
        action: "update",
        entity_id: "sc",
        changes: [%{"path" => "commanding_enabled", "value" => nil}]
      },
      %{
        kind: "spacecraft",
        action: "update",
        entity_id: "sc",
        changes: [%{"path" => "display_name", "value" => "B"}]
      }
    ]

    assert {:error, errors} = SpacecraftOps.prepare(ctx.org, ctx.mission, ops)

    assert Map.keys(errors) |> Enum.sort() ==
             ["ops.0.document.telemetry_enabled", "ops.1.changes.commanding_enabled"]

    assert {:ok, [_ | _]} = SpacecraftOps.prepare(ctx.org, ctx.mission, Enum.drop(ops, 2))
  end

  test "a profile without a version means its latest", ctx do
    profile_id = "profile-" <> unique("latest")

    apply_ops(ctx, [
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: profile_id,
        document: profile_doc("Latest")
      }
    ])

    create = %{
      kind: "spacecraft",
      action: "create",
      document: %{"display_name" => "A", "spacecraft_type_id" => profile_id}
    }

    update = %{
      kind: "spacecraft",
      action: "update",
      entity_id: "sc",
      changes: [%{"path" => "spacecraft_type_id", "value" => profile_id}]
    }

    pinned = put_in(create, [:document, "spacecraft_type_version"], 7)
    other = %{kind: "transport", action: "create", document: %{}}

    assert {:ok, [created, updated, ^pinned, ^other]} =
             SpacecraftOps.prepare(ctx.org, ctx.mission, [create, update, pinned, other])

    assert created.document["spacecraft_type_version"] == 1
    assert %{"path" => "spacecraft_type_version", "value" => 1} in updated.changes
  end

  test "an unknown profile is left for the kind to refuse", ctx do
    op = %{
      kind: "spacecraft",
      action: "create",
      document: %{"spacecraft_type_id" => "profile-nope"}
    }

    assert {:ok, [^op]} = SpacecraftOps.prepare(ctx.org, ctx.mission, [op])
  end

  defp apply_ops(%{alice: alice, mission: mission}, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: "Profile"}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test profile",
        expected_version: staged.version
      })
  end
end
