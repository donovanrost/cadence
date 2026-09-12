defmodule Cadence.Reads.ApplicationSurfaces.ContactRequirementListTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Management.Contacts.Store.ContactRequirementRow
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Spacecraft

  @org "org-requirement-list"
  @mission "mission-requirement-list"
  @craft "craft-requirement-list"
  @checker Path.expand(
             "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
             __DIR__
           )

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, "other-requirement-mission")

    user =
      User.new(%{
        user_id: "requirement-list-member",
        email: "list@example.test",
        display_name: "List member"
      })

    membership =
      OrganizationMembership.new(%{user_id: user.user_id, organization_id: @org, role: :member})

    scope =
      Scope.new(%{
        user: user,
        organization_id: @org,
        organization: organization,
        organization_membership: membership
      })

    assert {:ok, _} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @org,
               Spacecraft.new(%{
                 spacecraft_id: @craft,
                 mission_id: @mission,
                 display_name: "List spacecraft"
               })
             )

    %{scope: scope}
  end

  test "the real producer and Vue render current immutable content and actual lifecycle", %{
    scope: scope
  } do
    assert {:ok, requirement, _} =
             ContactRequirements.create(scope, @mission, attrs("requirement-01"))

    assert {:ok, _, _} =
             ContactRequirements.version(
               scope,
               @mission,
               requirement.contact_requirement_id,
               1,
               %{minimum_duration_seconds: 3601, priority: :critical}
             )

    assert {:ok, _} =
             ContactRequirements.close(
               scope,
               @mission,
               requirement.contact_requirement_id,
               2,
               "Complete"
             )

    props = props(scope)
    [row] = props["requirements"]
    assert props["contract_version"] == 1
    assert row["version_direction"] == "v2 · downlink"
    assert row["outcome_detail"] == "At least 3601 seconds"
    assert row["priority"]["tone"] == "error"
    assert row["lifecycle"]["label"] == "Closed"
    assert row["window"]["detail"] =~ "2027-01-01T01:00:01"
    assert row["detail_href"] == "/missions/#{@mission}/ops/requirements/requirement-01"
    assert props(scope, %{"state" => "active"})["requirements"] == []
    assert props(scope, %{"state" => "closed"})["requirements"] == [row]

    render(props, [row["__dom_id"]], [
      "contact-requirements-empty",
      "contact-requirements-unavailable"
    ])
  end

  test "pages are bounded and navigation retains the selected lifecycle", %{scope: scope} do
    for index <- 1..26 do
      id = "requirement-" <> String.pad_leading(to_string(index), 2, "0")
      assert {:ok, _, _} = ContactRequirements.create(scope, @mission, attrs(id))
    end

    first = props(scope, %{"state" => "active"})
    assert length(first["requirements"]) == 25
    assert first["pagination"]["previous_href"] == nil

    assert first["pagination"]["next_href"] ==
             "/missions/#{@mission}/ops/requirements?page=2&state=active"

    second = props(scope, %{"page" => "2", "state" => "active"})
    assert [%{"id" => "requirement-26"}] = second["requirements"]
    assert second["pagination"]["next_href"] == nil

    assert second["pagination"]["previous_href"] ==
             "/missions/#{@mission}/ops/requirements?page=1&state=active"

    render(second, ["requirements-previous-page"], ["requirements-next-page"])
  end

  test "empty results remain distinguishable from unavailable current versions", %{scope: scope} do
    empty = props(scope)
    assert empty["requirements"] == []
    render(empty, ["contact-requirements-empty"], ["contact-requirements-unavailable"])
    assert {:ok, _, _} = ContactRequirements.create(scope, @mission, attrs("broken-current"))

    from(row in ContactRequirementRow,
      where: row.organization_id == ^@org and row.mission_id == ^@mission
    )
    |> Repo.update_all(set: [current_version: 99])

    assert {:error, :unsupported_application_surface_query} = load(scope)
  end

  test "query admission and mission scope reject foreign or malformed requests", %{scope: scope} do
    assert {:ok, _} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @org,
               Spacecraft.new(%{
                 spacecraft_id: "other-list-craft",
                 mission_id: "other-requirement-mission",
                 display_name: "Other spacecraft"
               })
             )

    assert {:ok, _, _} =
             ContactRequirements.create(
               scope,
               "other-requirement-mission",
               Map.put(attrs("foreign-requirement"), :spacecraft_id, "other-list-craft")
             )

    assert props(scope)["requirements"] == []

    for params <- [
          %{"page" => "0"},
          %{"page" => 2},
          %{"page" => "1.5"},
          %{"page" => "01"},
          %{"page" => "1000001"},
          %{"state" => "paused"},
          %{"unknown" => "x"},
          %{"mission_id" => "other-requirement-mission"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(scope, params)
    end

    assert {:error, :unsupported_application_surface_query} =
             load(%{scope | mission_id: "other-requirement-mission"})

    assert {:error, :unsupported_application_surface_query} =
             load(%{scope | organization_id: "foreign"})
  end

  defp props(scope, params \\ %{}) do
    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{"component" => "OpsContactRequirementList", "props" => props}
              }
            }} = load(scope, params)

    props
  end

  defp load(scope, params \\ %{}) do
    OpsConsole.load(scope, HostContext.mission(@mission), %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "contact_requirement_list",
      surface_version: 1,
      query_id: "cadence.ops.contact_requirement_list",
      query_version: 1,
      params: params
    })
  end

  defp attrs(id),
    do: %{
      contact_requirement_id: id,
      spacecraft_id: @craft,
      contact_intent: "payload_downlink",
      service_direction: :downlink,
      earliest_start: ~U[2027-01-01 01:00:01Z],
      latest_end: ~U[2027-01-02 01:00:02Z],
      success_measure: :minimum_duration,
      minimum_duration_seconds: 60,
      priority: :high,
      rationale: "Requirement list test"
    }

  defp render(props, present, absent) do
    model = %{
      component: "OpsContactRequirementList",
      props: props,
      expected: %{presentIds: present, absentIds: absent}
    }

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @checker, Jason.encode!([model])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
