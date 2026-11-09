defmodule CadenceWeb.Console.SettingsAPITest do
  @moduledoc "ST1 Settings."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    %{
      admin: admin,
      member: member,
      mission_base: "/api/console/v1/missions/#{mission.mission_id}/settings",
      org_base: "/api/console/v1/organizations/#{org.organization_id}/settings"
    }
  end

  defp read(user, path),
    do:
      user |> TestFixtures.member_conn() |> get(path) |> json_response(200) |> Map.fetch!("data")

  defp put_json(user, path, body), do: user |> TestFixtures.member_conn() |> put(path, body)

  defp field(data, section, path) do
    data["sections"]
    |> Enum.find(&(&1["key"] == section))
    |> Map.fetch!("fields")
    |> Enum.find(&(&1["path"] == path))
  end

  test "a mission override reads as mission-sourced and resets to inherited", c do
    data = read(c.admin, c.mission_base)
    assert data["permissions"] == ["settings.edit"]
    keys = Enum.map(data["sections"], & &1["key"])
    assert "cadence.governance" in keys and "cadence.configuration" in keys

    framing = field(data, "cadence.configuration", "profile_framing_generations")

    assert %{
             "type" => "boolean",
             "value" => true,
             "source" => "organization",
             "inherited_value" => true
           } = framing

    put =
      put_json(c.admin, c.mission_base <> "/cadence.configuration", %{
        "values" => %{"profile_framing_generations" => false},
        "expected_version" => 0
      })

    assert %{"version" => 1, "state" => "active"} = json_response(put, 201)["data"]

    after_put = read(c.admin, c.mission_base)

    assert %{"value" => false, "source" => "mission"} =
             field(after_put, "cadence.configuration", "profile_framing_generations")

    section = Enum.find(after_put["sections"], &(&1["key"] == "cadence.configuration"))
    assert %{"version" => 1, "actor" => %{"name" => "Ada"}} = section["version"]

    stale =
      put_json(c.admin, c.mission_base <> "/cadence.configuration", %{
        "values" => %{"profile_framing_generations" => true},
        "expected_version" => 0
      })

    assert json_response(stale, 409)["error"]["code"] == "version_conflict"

    reset =
      put_json(c.admin, c.mission_base <> "/cadence.configuration", %{
        "values" => %{"profile_framing_generations" => nil},
        "expected_version" => 1
      })

    assert json_response(reset, 201)

    assert %{"value" => true, "source" => "organization"} =
             field(
               read(c.admin, c.mission_base),
               "cadence.configuration",
               "profile_framing_generations"
             )
  end

  test "the organization level has allow_override; bad values and unknown fields are refused",
       c do
    data = read(c.admin, c.org_base)

    assert %{"type" => "boolean", "value" => true} =
             field(data, "cadence.governance", "allow_override")

    bad =
      put_json(c.admin, c.org_base <> "/cadence.governance", %{
        "values" => %{"approval_requirement" => "sometimes"}
      })

    assert json_response(bad, 422)["error"]["code"] == "invalid_params"

    unknown =
      put_json(c.admin, c.org_base <> "/cadence.governance", %{"values" => %{"nope" => 1}})

    assert %{"details" => %{"nope" => _}} = json_response(unknown, 422)["error"]

    assert json_response(put_json(c.admin, c.org_base <> "/no.such", %{"values" => %{}}), 404)
  end
end
