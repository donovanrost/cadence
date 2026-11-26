defmodule CadenceWeb.Console.ConfigRollbackAPITest do
  @moduledoc "Change-set rollback endpoints (DECISIONS #49)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    alice = TestFixtures.persist_user!(display_name: "Alice")
    TestFixtures.grant_membership!(alice, org)
    mission = TestFixtures.persist_mission!(org)
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: false)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)
    %{alice: alice, base: "/api/v1/missions/#{mission.mission_id}/config"}
  end

  defp call(c, :get, path), do: c.alice |> TestFixtures.member_conn() |> get(c.base <> path)

  defp call(c, :post, path, body),
    do: c.alice |> TestFixtures.member_conn() |> post(c.base <> path, body)

  defp apply!(c, ops, summary) do
    staged =
      c
      |> call(:post, "/stage", %{"summary" => summary, "ops" => ops})
      |> json_response(201)
      |> Map.fetch!("data")

    c
    |> call(:post, "/change-sets/#{staged["change_set_id"]}/submit", %{
      "reason" => "Reason for this change",
      "expected_version" => staged["version"]
    })
    |> json_response(200)

    staged
  end

  test "preview, stage and apply a rollback; refusals are coded", c do
    %{"entity_ids" => [id]} =
      apply!(
        c,
        [
          %{
            "kind" => "ground_station",
            "action" => "create",
            "document" => %{"display_name" => "Svalbard", "region" => "Arctic"}
          }
        ],
        "Add"
      )

    apply!(
      c,
      [
        %{
          "kind" => "ground_station",
          "action" => "update",
          "entity_id" => id,
          "changes" => [%{"path" => "display_name", "value" => "Svalbard B"}]
        }
      ],
      "Rename"
    )

    # Readiness R2 lists the applied revisions, newest first.
    assert [
             %{"version_label" => "r3", "summary" => "Rename", "actor" => %{"name" => "Alice"}}
             | _
           ] =
             c.alice
             |> TestFixtures.member_conn()
             |> get(String.replace_suffix(c.base, "/config", "/readiness"))
             |> json_response(200)
             |> get_in(["data", "recent_changes"])

    preview = c |> call(:get, "/rollback?to=2") |> json_response(200) |> Map.fetch!("data")

    assert %{
             "target" => 2,
             "head" => 3,
             "reverts" => [3],
             "summary" => "Roll back to r2 (reverts r3)",
             "ops" => [%{"kind" => "ground_station", "entity_id" => ^id, "action" => "update"}],
             "outside" => [],
             "preview" => %{"verdict" => "go"}
           } = preview

    # Display fields for the console's sentences.
    assert [%{"entity_name" => "Svalbard B", "fields" => fields}] = preview["preview"]["diffs"]
    assert %{"label" => "Name"} = Enum.find(fields, &(&1["path"] == "display_name"))

    staged =
      c |> call(:post, "/rollback", %{"to" => 2}) |> json_response(200) |> Map.fetch!("data")

    assert %{"change_set_id" => set_id, "version" => version} = staged

    assert %{"state" => "applied", "revision" => 4} =
             c
             |> call(:post, "/change-sets/#{set_id}/submit", %{
               "reason" => "Undo the rename",
               "expected_version" => version
             })
             |> json_response(200)
             |> Map.fetch!("data")

    revision = c |> call(:get, "/revisions/4") |> json_response(200) |> Map.fetch!("data")
    assert %{"kind" => "rollback", "rolls_back_to" => 2} = revision
    assert [%{"entity_name" => "Svalbard"}] = revision["entries"]

    assert json_response(call(c, :get, "/rollback?to=4"), 422)["error"]["code"] ==
             "invalid_rollback_target"

    assert json_response(call(c, :get, "/rollback?to=x"), 422)["error"]["code"] ==
             "invalid_params"
  end
end
