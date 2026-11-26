defmodule Cadence.Management.Commanding.ExactArgumentAuthoringTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    RequestStore,
    RequestValidation
  }

  alias Cadence.Control.Commanding
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures

  alias Cadence.Management.Commanding.RequestAuthoring

  @maximum 18_446_744_073_709_551_615
  @minimum -9_223_372_036_854_775_808
  setup do
    Fixtures.fixture!()
  end

  test "imported unsigned defaults, explicit unsigned and signed integers survive preview, encoding and persistence",
       c do
    for {command, values, resolved, bytes} <- [
          {"SET_COUNTER", %{"amount" => 2}, %{"amount" => 2, "counter" => @maximum},
           <<1, 2, @maximum::unsigned-big-64>>},
          {"SET_COUNTER", %{"amount" => 3, "counter" => @maximum},
           %{"amount" => 3, "counter" => @maximum}, <<1, 3, @maximum::unsigned-big-64>>},
          {"SET_SIGNED", %{"counter" => @minimum}, %{"counter" => @minimum},
           <<2, @minimum::signed-big-64>>},
          {"SET_ENUM", %{"counter" => @maximum}, %{"counter" => @maximum},
           <<3, @maximum::unsigned-big-64>>},
          {"SET_ENUM", %{"counter" => Integer.to_string(@maximum)},
           %{"counter" => Integer.to_string(@maximum)}, <<3, @maximum::unsigned-big-64>>}
        ] do
      assert {:ok, held} =
               RequestAuthoring.preview(c.scope, c.mission, Fixtures.input(c, command, values))

      assert held.request.argument_values == values
      assert held.request.resolved_argument_values == resolved
      assert encoded(c, held.request) == bytes
      public = RequestAuthoring.public_preview(held)
      assert Jason.decode!(public["argument_values_json"]) == values
      assert Jason.decode!(public["resolved_argument_values_json"]) == resolved
      refute Map.has_key?(public, "resolved_argument_values")

      assert {:ok, receipt} =
               RequestAuthoring.create(c.scope, c.mission, held, %{
                 "expected_preview" => held.token
               })

      assert {:ok, stored} = RequestStore.fetch_request(c.org, c.mission, receipt["request_id"])
      assert stored == held.request
    end

    assert Repo.aggregate(CommandQueueEntryRow, :count) == 0
    assert Repo.aggregate(CommandReleaseAttemptRow, :count) == 0
  end

  test "catalog carries exact default text and wire range checks still reject out-of-range values",
       c do
    assert {:ok, catalog} =
             RequestAuthoring.load(c.scope, c.mission, %{
               "command" => c.model.commands_by_name["SET_COUNTER"]
             })

    assert catalog["version"] == 2
    counter = Enum.find(catalog["selected_command"]["arguments"], &(&1["name"] == "counter"))
    assert counter["default_value_json"] == Integer.to_string(@maximum)
    refute Map.has_key?(counter, "default_value")

    for {command, values} <- [
          {"SET_COUNTER", %{"amount" => 2, "counter" => @maximum + 1}},
          {"SET_COUNTER", %{"amount" => 2, "counter" => -1}},
          {"SET_SIGNED", %{"counter" => @minimum - 1}},
          {"SET_SIGNED", %{"counter" => -@minimum}},
          {"SET_ENUM", %{"counter" => @maximum + 1}}
        ] do
      assert {:error, _} =
               RequestAuthoring.preview(c.scope, c.mission, Fixtures.input(c, command, values))
    end

    assert Repo.aggregate(CommandRequestRow, :count) == 0
  end

  defp encoded(c, request) do
    {:ok, basis} =
      RequestValidation.resolve_basis(
        c.org,
        c.mission,
        request.mission_model_revision_id,
        request.command_id
      )

    {:ok, %{binary: bytes}} =
      Commanding.encode_command(
        basis.runtime_definition,
        request.resolved_argument_values
      )

    bytes
  end
end
