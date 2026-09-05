defmodule CadenceWeb.CommsOverviewPresenterTest do
  use ExUnit.Case, async: true

  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias CadenceWeb.{CommsOverviewPresenter, CommsValidation}

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

    assert is_binary(Jason.encode!(presentation))

    assert presentation["root"]["attrs"] == %{
             "class" => "space-y-6",
             "id" => "comms-overview-page"
           }

    assert presentation["overview"][:transport][:empty]
    assert presentation["overview"][:validation][:empty]
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

  test "fails closed for an oversized persisted mission display name" do
    mission =
      Mission.new(%{
        mission_id: "mission-presenter-bounds",
        organization_id: "organization-presenter-bounds",
        slug: "presenter-bounds",
        display_name: String.duplicate("x", 241)
      })

    presentation =
      CommsOverviewPresenter.presentation(mission, %{
        transports: [],
        transport_count: 0,
        findings: [],
        finding_groups: []
      })

    assert presentation["header"]["title"]["text"] == "Mission unavailable"
    assert is_binary(Jason.encode!(presentation))
  end

  test "renders validation provider failures as blocked and non-empty" do
    mission =
      Mission.new(%{
        mission_id: "mission-presenter-failure",
        organization_id: "organization-presenter-failure",
        slug: "presenter-failure",
        display_name: "Presenter Failure Mission"
      })

    presentation =
      CommsOverviewPresenter.build(%Scope{organization_id: nil}, mission)

    validation = presentation["overview"][:validation]

    assert validation[:status] == %{tone: "blocked", label: "Validation unavailable"}
    refute validation[:empty]
    refute validation[:empty_state][:title] == "All clear"
    assert [%{findings: [%{id: "comms-validation-unavailable"}]}] = validation[:finding_groups]
  end

  test "preserves core validation errors for the dedicated validation adapter" do
    assert {:error, :authenticated_user_required} =
             CommsValidation.findings_for_mission(%Scope{organization_id: nil}, "mission-failure")
  end
end
