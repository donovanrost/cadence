defmodule CadenceWeb.OpsCommandReviewExactValuesTest do
  use CadenceWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source
  alias Cadence.CommandAuthoringFixtures

  alias Cadence.Commanding.{
    CommandApprovalRow,
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow
  }

  alias Cadence.Ids
  alias Cadence.Management.Commanding
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.MissionModelFixtures
  alias Cadence.MissionModels
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  @maximum 18_446_744_073_709_551_615
  @probe Path.expand(
           "../../../../frontend/modules/commanding/src/features/command-review/producer-consumer-probe.mjs",
           __DIR__
         )

  test "a native unsigned64 default is shown exactly before the actual human approval" do
    org = TestFixtures.persist_org!()
    author = TestFixtures.persist_user!()
    reviewer = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(author, org, role: :organization_admin)
    TestFixtures.grant_membership!(reviewer, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    model = model!(org.organization_id, mission.mission_id)
    target = CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id)

    scope =
      Scope.new(%{
        user: author,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    {:ok, catalog} = RequestAuthoring.load(scope, mission.mission_id, %{})

    {:ok, preview} =
      RequestAuthoring.preview(scope, mission.mission_id, %{
        "expected_basis" => catalog["basis"]["token"],
        "command_id" => model.commands_by_name["SET_COUNTER"],
        "source_endpoint_ref" => target.source_endpoint_id,
        "argument_values_json" => Jason.encode!(%{"amount" => 2}),
        "priority" => 3,
        "not_before" => nil,
        "expires_at" => nil
      })

    {:ok, created} =
      RequestAuthoring.create(scope, mission.mission_id, preview, %{
        "expected_preview" => preview.token
      })

    request_id = created["request_id"]
    request = Repo.get!(CommandRequestRow, request_id) |> CommandRequestRow.to_domain()
    assert request.resolved_argument_values == %{"amount" => 2, "counter" => @maximum}
    path = "/missions/#{mission.mission_id}/ops/commands/requests/#{request_id}"
    {:ok, view, _} = live(TestFixtures.member_conn(reviewer), path)
    p = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert p["status"] == "ready"
    dto = p["data"]["review"]["request"]
    assert dto["resolved_argument_values_json"] =~ "18446744073709551615"
    refute Map.has_key?(dto, "resolved_argument_values")
    {output, code} = System.cmd("node", [@probe, Jason.encode!(p)], stderr_to_stdout: true)
    assert code == 0, output
    [_, encoded] = Regex.run(~r/COMMAND_REVIEW_INPUT=([A-Za-z0-9+\/=]+)/, output)
    input = encoded |> Base.decode64!() |> Jason.decode!()
    assert input["expected_review"] == p["data"]["review"]["expected_review"]

    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => "decide",
      "input" => input
    })

    assert_reply(view, %{ok: true, snapshot: %{status: "completed", receipt: receipt}})
    assert receipt["actor_id"] == reviewer.user_id

    {:ok, approved} =
      Commanding.fetch_approved_command(org.organization_id, mission.mission_id, request_id)

    assert approved.resolved_argument_values == request.resolved_argument_values
    assert approved.approved_by["user_id"] == reviewer.user_id

    assert Repo.aggregate(
             from(r in CommandApprovalRow, where: r.command_request_id == ^request_id),
             :count
           ) == 1

    for schema <- [CommandQueueEntryRow, CommandReleaseAttemptRow] do
      refute Repo.exists?(from(r in schema, where: r.command_request_id == ^request_id))
    end
  end

  defp model!(org, mission) do
    yaml = """
    commands:
      - name: SET_COUNTER
        opcode: 1
        is_hazardous: true
        hazard_description: Changes the spacecraft counter
        requires_confirmation: true
        parameters:
          - name: amount
            data_type: uint
            required: true
            bit_offset: 0
            bit_length: 8
          - name: counter
            data_type: uint
            required: false
            default_value: #{@maximum}
            bit_offset: 8
            bit_length: 64
    """

    source =
      Source.new(%{
        artifact_id: Ids.new("exact_model"),
        organization_id: org,
        mission_id: mission,
        catalog_family: :combined,
        artifact_name: "commands.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: yaml
      })

    {:ok, imported} =
      CadenceYamlDatabase.import(source, %{import_run_id: Ids.new("exact_import")})

    {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)

    MissionModelFixtures.activate_imported_model!(org, mission, %{
      "mission_model" => %{"revision_id" => compilation.revision.revision_id}
    })
  end
end
