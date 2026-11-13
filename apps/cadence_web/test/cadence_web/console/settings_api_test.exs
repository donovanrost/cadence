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

  test "exact shape of a section, a field and the organization's allow_override", c do
    section =
      read(c.admin, c.mission_base)["sections"]
      |> Enum.find(&(&1["key"] == "cadence.pass_review"))

    assert section |> Map.keys() |> Enum.sort() ==
             ~w(fields key locked purpose title version)

    assert %{"title" => "Pass review", "locked" => false, "version" => nil} = section
    assert is_binary(section["purpose"])

    assert [threshold, target] = section["fields"]

    assert threshold == %{
             "path" => "pass_realized_threshold",
             "label" => "A pass counts as realized at",
             "type" => "number",
             "unit" => "ratio",
             "enum" => nil,
             "range" => %{"min" => 0, "max" => 1},
             "required" => false,
             "help" => "The share of its planned window it must fly.",
             "visible_when" => nil,
             "value" => 0.95,
             "source" => "organization",
             "inherited_value" => 0.95
           }

    assert target["path"] == "realization_target"

    allow =
      read(c.admin, c.org_base)["sections"]
      |> Enum.find(&(&1["key"] == "cadence.pass_review"))
      |> Map.fetch!("fields")
      |> List.last()

    assert allow == %{
             "path" => "allow_override",
             "label" => "Missions may override",
             "type" => "boolean",
             "unit" => nil,
             "enum" => nil,
             "range" => nil,
             "required" => false,
             "help" => nil,
             "visible_when" => nil,
             "value" => true,
             "source" => "organization",
             "inherited_value" => nil
           }
  end

  test "a mission sets single fields; the others follow the organization (per-field)", c do
    put =
      put_json(c.admin, c.mission_base <> "/cadence.pass_review", %{
        "values" => %{"pass_realized_threshold" => 0.9},
        "expected_version" => 0
      })

    assert json_response(put, 201)
    data = read(c.admin, c.mission_base)

    assert %{"value" => 0.9, "source" => "mission"} =
             field(data, "cadence.pass_review", "pass_realized_threshold")

    assert %{"value" => 0.98, "source" => "organization"} =
             field(data, "cadence.pass_review", "realization_target")

    org =
      put_json(c.admin, c.org_base <> "/cadence.pass_review", %{
        "values" => %{"realization_target" => 0.97}
      })

    assert json_response(org, 201)

    assert %{"value" => 0.97, "source" => "organization"} =
             field(read(c.admin, c.mission_base), "cadence.pass_review", "realization_target")

    reset =
      put_json(c.admin, c.mission_base <> "/cadence.pass_review", %{
        "values" => %{"pass_realized_threshold" => nil},
        "expected_version" => 1
      })

    assert json_response(reset, 201)

    assert %{"value" => 0.95, "source" => "organization"} =
             field(
               read(c.admin, c.mission_base),
               "cadence.pass_review",
               "pass_realized_threshold"
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
