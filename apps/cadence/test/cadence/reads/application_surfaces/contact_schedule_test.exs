defmodule Cadence.Reads.ApplicationSurfaces.ContactScheduleTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.ContactScheduleFixtures, as: Fixtures
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Reads.ApplicationSurfaces.Planning.ContactSchedule

  @renderer Path.expand(
              "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
              __DIR__
            )
  setup do: Fixtures.setup_schedule()

  test "loads selected scoped spacecraft and real pinned route through the public Vue module",
       c do
    assert {:ok, %{schedule: schedule}} =
             ContactSchedule.load(c.scope, c.mission, %{
               "spacecraft_id" => c.spacecraft.spacecraft_id
             })

    assert schedule.selected_spacecraft.id == c.spacecraft.spacecraft_id
    assert [route] = schedule.routes.entries
    assert route.evidence == ProviderScheduling.route_evidence(c.route)
    refute Jason.encode!(schedule) =~ "credential"
    assert schedule.scheduled.entries == []
    assert schedule.reservations.entries == []

    {output, status} =
      System.cmd(
        "node",
        [
          @renderer,
          Jason.encode!([
            %{
              component: "OpsContactSchedule",
              props: %{schedule: schedule},
              expected: %{
                presentIds: [
                  "ops-contact-schedule-page",
                  "contact-search",
                  "contact-selected-spacecraft"
                ]
              }
            }
          ])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "unselected and filtered empty pages remain usable and do not invent route readiness", c do
    assert {:ok, %{schedule: schedule}} =
             ContactSchedule.load(c.scope, c.mission, %{
               "spacecraft_q" => "does-not-exist",
               "scheduled_page" => "2"
             })

    assert schedule.selected_spacecraft == nil
    assert schedule.routes.entries == []
    assert schedule.spacecraft.entries == []
    assert schedule.scheduled.page == 2

    assert {:error, :spacecraft_not_found} =
             ContactSchedule.load(c.scope, c.mission, %{"spacecraft_id" => "foreign"})
  end

  test "public surface preserves host scope and rejects revoked access", c do
    request = %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "contact_schedule",
      surface_version: 1,
      query_id: "cadence.ops.contact_schedule",
      query_version: 1,
      params: %{}
    }

    host = HostContext.mission(c.mission_id)

    assert {:ok, %{"data" => %{"presentation" => %{"props" => %{"schedule" => model}}}}} =
             OpsConsole.load(c.scope, host, request)

    assert model["context"]["mission_id"] == c.mission_id
    assert model["permissions"] == %{"operate" => true, "cancel" => true}

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %{c.scope | organization_membership: nil},
               host,
               request
             )

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(c.scope, host, %{
               request
               | params: %{"mission_id" => "foreign"}
             })
  end

  test "rejects unknown, noncanonical and unbounded query input" do
    for q <- [
          %{"unknown" => "value"},
          %{"scheduled_page" => "01"},
          %{"realized_page" => "1000001"},
          %{"routes_page" => "0"},
          %{"spacecraft_id" => ""},
          %{"spacecraft_q" => String.duplicate("a", 121)},
          %{"reservations_page" => 1}
        ] do
      assert {:error, :invalid_contact_schedule_query} = ContactSchedule.admit_query(q)
    end
  end
end
