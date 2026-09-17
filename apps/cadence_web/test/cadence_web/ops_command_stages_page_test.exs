defmodule CadenceWeb.OpsCommandStagesPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandRequestRow,
    CommandStage,
    CommandStageRow,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Repo
  alias CadenceWeb.{HostTransportTestSupport, TestFixtures}

  @probe Path.expand(
           "../../../../frontend/modules/commanding/src/shared/stages/producer-consumer-probe.mjs",
           __DIR__
         )
  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    member = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = CommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)
    target = CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id)

    %{
      org: org.organization_id,
      organization: org,
      user: user,
      member: member,
      mission: mission.mission_id,
      model: model,
      target: target
    }
  end

  test "real Vue creation, repeated draft authoring and reviewed submission persist exact effects",
       c do
    path = "/missions/#{c.mission}/ops/commands/stages/new"
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    p = context_page(view, c.mission, "commanding.stage-create")
    assert p["status"] == "ready"
    %{"event" => "create", "input" => input} = probe(p, "create")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, path, p, "create", input)

    stage_id = receipt["stage_id"]
    row = Repo.get!(CommandStageRow, stage_id)
    assert row.description == String.duplicate("é", 2_000)
    assert get_in(row.owner_document, ["value", "user_id"]) == c.user.user_id
    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, path, p, "create", input)
    assert %{"snapshot" => created} = read(view, path, p)
    assert created["data"]["write_token"] == nil
    assert created["data"]["operation"]["receipt"] == receipt

    path = workbench_path(c, stage_id)
    p = navigate(view, path)
    assert p["id"] == "commanding.stage-workbench"
    assert p["status"] == "ready"

    {p, first_id} = create_draft(view, path, p)
    first_nonce = p["data"]["write_token"]
    {p, second_id} = create_draft(view, path, p)
    refute first_id == second_id
    refute p["data"]["write_token"] == first_nonce
    assert request_count(c) == 0

    %{"event" => "preview_batch", "input" => input} = probe(p, "preview_batch")

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, path, p, "preview_batch", input)

    assert [request_preview] = preview["requests"]

    assert Jason.decode!(request_preview["resolved_argument_values_json"]) == %{
             "amount" => 2,
             "delay_s" => 5
           }

    assert %{"snapshot" => p} = read(view, path, p)
    %{"event" => "submit", "input" => input} = probe(p, "submit")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, path, p, "submit", input)

    assert request_count(c) == 1
    assert Repo.get!(CommandStageRow, stage_id).lifecycle_state == "draft"
    assert [%{"request_id" => request_id, "item_id" => item_id}] = receipt["requests"]
    assert item_id in [first_id, second_id]
    request = Repo.get!(CommandRequestRow, request_id) |> CommandRequestRow.to_domain()
    assert request.requested_by == %{"actor_kind" => "user", "user_id" => c.user.user_id}
    assert request.source_staged_command_item_id == item_id
    assert request.source_command_stage_id == stage_id
    assert request.resolved_argument_values == %{"amount" => 2, "delay_s" => 5}
    assert %{"snapshot" => %{"status" => "rejected"}} = action(view, path, p, "submit", input)
    assert %{"snapshot" => result} = read(view, path, p)
    assert result["data"]["operation"]["receipt"] == receipt
    assert result["data"]["batch_preview"] == nil
  end

  test "draft maintenance survives unavailable model while stale tokens, departure and revocation fail closed",
       c do
    stage = stage!(c)
    path = workbench_path(c, stage.command_stage_id)
    {:ok, view, _} = live(TestFixtures.member_conn(c.user), path)
    p = context_page(view, c.mission, "commanding.stage-workbench")
    {p, item_id} = create_draft(view, path, p)
    old_nonce = p["data"]["write_token"]
    selected_path = workbench_path(c, stage.command_stage_id, %{"item" => item_id})
    current = navigate(view, selected_path)
    refute current["token"] == p["token"]

    assert %{"ok" => false} =
             action(view, path, p, "edit_details", %{"expected_write" => old_nonce})

    Repo.delete!(Repo.get!(ActiveBindingSetRow, c.mission))
    assert %{"snapshot" => current} = read(view, selected_path, current)
    assert current["data"]["catalog"] == nil
    %{"event" => "edit_details", "input" => input} = probe(current, "edit_details")

    assert %{"snapshot" => %{"status" => "completed"}} =
             action(view, selected_path, current, "edit_details", input)

    row = Repo.get!(StagedCommandItemRow, item_id)
    assert row.notes == "Current operator note"
    assert row.item_order == 9
    assert request_count(c) == 0

    assert %{"snapshot" => %{"status" => "rejected"}} =
             action(view, selected_path, current, "edit_details", input)

    Repo.update_all(
      from(row in OrganizationMembershipRow,
        where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    render_hook(view, "host:ops-page:read", %{
      "path" => selected_path,
      "id" => current["id"],
      "token" => current["token"]
    })

    assert_redirect(view, "/no-organization")
    assert request_count(c) == 0
  end

  test "shared directory admission never exposes another human's private stage", c do
    private = stage!(c)

    {:ok, shared} =
      StageStore.persist_stage(c.org, %{
        private
        | command_stage_id: Cadence.Ids.new("stage"),
          visibility: :shared
      })

    other = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(other, c.organization, role: :organization_admin)
    path = "/missions/#{c.mission}/ops/commands/stages"
    {:ok, view, _} = live(TestFixtures.member_conn(other), path)
    p = context_page(view, c.mission, "commanding.stages")
    assert [%{"id" => shared_id}] = p["data"]["directory"]["stages"]["entries"]
    assert shared_id == shared.command_stage_id
    private_page = navigate(view, workbench_path(c, private.command_stage_id))
    assert private_page["status"] == "unavailable"
    assert %{"ok" => false} = action(view, path, p, "create", %{})
  end

  defp create_draft(view, path, p) do
    %{"event" => "preview_item", "input" => input} = probe(p, "preview_item")

    assert %{"snapshot" => %{"status" => "previewed", "preview" => preview}} =
             action(view, path, p, "preview_item", input)

    assert %{"snapshot" => with_preview} = read(view, path, p)
    assert with_preview["data"]["item_preview"] == preview
    %{"event" => "save_item", "input" => input} = probe(with_preview, "save_item")

    assert %{"snapshot" => %{"status" => "completed", "receipt" => receipt}} =
             action(view, path, p, "save_item", input)

    assert receipt["item_id"] == preview["item_id"]
    row = Repo.get!(StagedCommandItemRow, receipt["item_id"])
    assert row.notes == String.duplicate("é", 2_000)
    assert row.argument_values_document == %{"value" => %{"amount" => 2, "delay_s" => 5}}
    assert row.submitted_command_request_id == nil
    assert %{"snapshot" => refreshed} = read(view, path, p)
    assert refreshed["data"]["item_preview"] == nil
    refute refreshed["data"]["write_token"] == input["expected_write"]
    {refreshed, receipt["item_id"]}
  end

  defp stage!(c) do
    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Flight stage",
          owner: %{"user_id" => c.user.user_id}
        })
      )

    stage
  end

  defp workbench_path(c, id, params \\ %{}),
    do:
      "/missions/#{c.mission}/ops/commands/stages/#{id}?" <>
        URI.encode_query(
          Map.merge(
            %{
              "command" => c.model.commands_by_name["COMMAND_1"],
              "target" => c.target.source_endpoint_id
            },
            params
          )
        )

  defp request_count(c),
    do:
      Repo.aggregate(from(row in CommandRequestRow, where: row.mission_id == ^c.mission), :count)

  defp context_page(view, mission, id),
    do:
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => id,
        "mission_id" => mission
      })["ops_page"]

  defp navigate(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true, snapshot: snapshot})
    snapshot |> Jason.encode!() |> Jason.decode!() |> Map.fetch!("ops_page")
  end

  defp probe(page, mode) do
    path = Path.join(System.tmp_dir!(), "cadence-stage-producer-#{Ecto.UUID.generate()}.json")
    File.write!(path, Jason.encode!(page))

    try do
      {output, code} = System.cmd("node", [@probe, path, mode], stderr_to_stdout: true)
      assert code == 0, output
      [_, encoded] = Regex.run(~r/COMMAND_STAGE_INPUT=([A-Za-z0-9+\/=]+)/, output)
      encoded |> Base.decode64!() |> Jason.decode!()
    after
      File.rm!(path)
    end
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp read(view, path, page) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
