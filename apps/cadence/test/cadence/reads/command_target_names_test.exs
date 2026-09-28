defmodule Cadence.Reads.CommandTargetNamesTest do
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures, as: Fixtures
  alias Cadence.Control.Commanding.QueueSubmission
  alias Cadence.Reads.{CommandHistory, CommandMonitor, CommandReview, Commands}
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint

  test "command views resolve scoped display names while retaining exact target and review identities" do
    c = Fixtures.scope!()
    request = Fixtures.request!(c)
    id = request.source_endpoint_ref
    endpoint!(c, id, "Aurora")

    assert {:ok, monitor} = CommandMonitor.load(c.scope, c.mission, %{"query" => "aurora"})
    assert [%{target: ^id, target_name: "Aurora"}] = monitor.rows
    assert [%{id: ^id, name: "Aurora"}] = monitor.targets
    assert [%{target: ^id, target_name: "Aurora"}] = Commands.summary(c.org, c.mission).rows

    assert {:ok, history} =
             CommandHistory.load(c.scope, c.mission, request.command_request_id, %{})

    assert history["request"]["target"] == id
    assert history["request"]["target_name"] == "Aurora"

    assert {:ok, review} = CommandReview.load(c.scope, c.mission, request.command_request_id)
    assert review["request"]["source_endpoint_ref"] == id
    assert review["target_name"] == "Aurora"
    assert {:ok, queue} = QueueSubmission.load(c.scope, c.mission, request.command_request_id)
    assert queue.model["request"]["source_endpoint_ref"] == id
    assert queue.model["target_name"] == "Aurora"

    Cadence.SourceEndpoints.SourceEndpointRow
    |> Repo.get!(id)
    |> Ecto.Changeset.change(display_name: "Aurora renamed")
    |> Repo.update!()

    assert {:ok, renamed} = CommandReview.load(c.scope, c.mission, request.command_request_id)
    assert renamed["target_name"] == "Aurora renamed"
    assert renamed["expected_review"] == review["expected_review"]
  end

  test "an unavailable endpoint retains command history without borrowing a foreign label" do
    c = Fixtures.scope!()
    request = Fixtures.request!(c)
    endpoint!(Fixtures.scope!(), request.source_endpoint_ref, "Foreign spacecraft")

    assert {:ok, monitor} = CommandMonitor.load(c.scope, c.mission, %{})
    assert [%{target_name: nil}] = monitor.rows
    assert hd(monitor.rows).target == request.source_endpoint_ref
    assert SourceEndpoints.display_names(c.org, c.mission, [request.source_endpoint_ref]) == %{}
  end

  defp endpoint!(c, id, name) do
    assert {:ok, _} =
             SourceEndpoints.persist_source_endpoint(
               c.org,
               SourceEndpoint.new(%{
                 source_endpoint_id: id,
                 organization_id: c.org,
                 mission_id: c.mission,
                 display_name: name
               })
             )
  end
end
