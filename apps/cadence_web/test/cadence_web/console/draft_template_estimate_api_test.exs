defmodule CadenceWeb.Console.DraftTemplateEstimateAPITest do
  @moduledoc """
  U52: the Start screen's template fan-out estimate on GET …/contact-plans/setup?day= (count,
  limit, the templates the per-run cap cuts short) and Start's refusal over the limit, with the
  whole count.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ContactPlanning.ContactRequirementTemplates
  alias Cadence.FleetStartFixtures, as: Fixtures
  alias CadenceWeb.TestFixtures

  setup do
    c = Fixtures.setup_start()
    user = TestFixtures.persist_user!(display_name: "Planner")
    TestFixtures.grant_membership!(user, c.organization, role: :organization_admin)

    Map.merge(c, %{
      conn: TestFixtures.member_conn(user),
      base: "/api/v1/missions/#{c.mission_id}/contact-plans"
    })
  end

  defp setup_read(c, query),
    do:
      c.conn
      |> get(c.base <> "/setup" <> query)
      |> json_response(200)
      |> get_in(["data", "setup"])

  defp template!(c) do
    {:ok, template, version} =
      ContactRequirementTemplates.create(c.admin, c.mission_id, Fixtures.template_attrs())

    {template.contact_requirement_template_id, version.name}
  end

  test "no active template: no estimate", c do
    assert setup_read(c, "?day=2030-07-17")["template_requirements_estimate"] == nil
  end

  test "the estimate for the day counts the capped occurrences and names the capped template",
       c do
    {id, name} = template!(c)

    # Hourly from 04:00 with a per-run cap of 10: the day keeps 04:00 to 13:00.
    assert %{
             "count" => 10,
             "limit" => 50_000,
             "capped" => [
               %{"template" => %{"id" => ^id, "name" => ^name}, "limit" => 10, "last_at" => last}
             ]
           } = setup_read(c, "?day=2030-07-17")["template_requirements_estimate"]

    assert {:ok, ~U[2030-07-17 13:00:00Z], 0} =
             DateTime.from_iso8601(String.slice(last, 0, 19) <> "Z")

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"day" => _}}} =
             c.conn |> get(c.base <> "/setup?day=17-07-2030") |> json_response(422)
  end

  test "Start over the limit is a 422 with the whole count and the limit", c do
    template!(c)
    template!(c)
    previous = Application.get_env(:cadence, :template_fan_out_limit)
    Application.put_env(:cadence, :template_fan_out_limit, 3)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :template_fan_out_limit, previous),
        else: Application.delete_env(:cadence, :template_fan_out_limit)
    end)

    assert %{
             "error" => %{
               "code" => "fleet_planning_occurrence_limit_exceeded",
               "details" => %{"count" => count, "limit" => 3}
             }
           } =
             c.conn
             |> post(c.base <> "/drafts", %{"day" => "2030-07-17", "operation_id" => "op-u52"})
             |> json_response(422)

    assert count == 20
  end
end
