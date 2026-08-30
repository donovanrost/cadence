defmodule CadenceWeb.CommsOverviewPresenterTest do
  use ExUnit.Case, async: true

  alias Cadence.Missions.Mission
  alias CadenceWeb.CommsOverviewPresenter

  test "preserves the exact empty Comms presentation as JSON-safe data" do
    mission =
      Mission.new(%{
        mission_id: "mission-presenter",
        organization_id: "organization-presenter",
        slug: "presenter",
        display_name: "Presenter Mission"
      })

    presentation =
      CommsOverviewPresenter.presentation(mission, %{
        transports: [],
        transport_count: 0,
        findings: [],
        finding_groups: []
      })

    assert Jason.decode!(Jason.encode!(presentation)) == presentation

    assert presentation["root"]["attrs"] == %{
             "class" => "space-y-6",
             "id" => "comms-overview-page"
           }

    assert presentation["overview"]["transport"]["empty"]
    assert presentation["overview"]["validation"]["empty"]
  end

  test "keeps presentation attribute semantics in the extracted presenter" do
    assert CommsOverviewPresenter.presentation_attrs(%{
             "nil" => nil,
             "false" => false,
             "true" => true,
             "string" => "retained",
             "number" => 7
           }) == %{
             "true" => "",
             "string" => "retained",
             "number" => "7"
           }
  end
end
