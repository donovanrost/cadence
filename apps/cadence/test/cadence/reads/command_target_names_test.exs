defmodule Cadence.Reads.CommandTargetNamesTest do
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures, as: Fixtures
  alias Cadence.Reads.Commands
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint

  test "the command summary resolves scoped display names while retaining the exact target identity" do
    c = Fixtures.scope!()
    request = Fixtures.request!(c)
    id = request.source_endpoint_ref
    endpoint!(c, id, "Aurora")

    assert [%{target: ^id, target_name: "Aurora"}] = Commands.summary(c.org, c.mission).rows
  end

  test "an unavailable endpoint keeps its target without borrowing another mission's label" do
    c = Fixtures.scope!()
    request = Fixtures.request!(c)
    endpoint!(Fixtures.scope!(), request.source_endpoint_ref, "Foreign spacecraft")

    assert [%{target: target, target_name: nil}] = Commands.summary(c.org, c.mission).rows
    assert target == request.source_endpoint_ref
    assert SourceEndpoints.display_names(c.org, c.mission, [request.source_endpoint_ref]) == %{}
  end

  defp endpoint!(c, id, name) do
    assert {:ok, _} =
             Cadence.SourceEndpointFixtures.persist(
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
