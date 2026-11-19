defmodule CadenceWeb.SettingsSectionsGoldenTest do
  @moduledoc """
  The server's settings sections against the committed golden
  (`test/support/golden/settings_sections.json`): `Cadence.Management.Settings` lists exactly the
  golden's non-console sections, and the console (`Cadence.Management.ConsoleSettings`, which
  silently leaves out a section it has no fields for) shows every one of them. The host half is
  `frontend/apps/host/src/settings/contributions.golden.test.ts`. A section added or removed on
  one side fails that side's test until the golden and the other side follow.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.Registry
  alias Cadence.Auth.Scope
  alias Cadence.Management.{ConsoleSettings, Settings}
  alias CadenceWeb.TestFixtures

  @golden_path Path.expand("../support/golden/settings_sections.json", __DIR__)
  @external_resource @golden_path
  @golden @golden_path |> File.read!() |> Jason.decode!() |> Map.fetch!("sections")

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        actor_kind: :user,
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    %{scope: scope, mission_id: mission.mission_id}
  end

  test "every application's declared settings section is in the golden, with its owner" do
    declared =
      for definition <- Registry.all(), section <- definition.settings_sections do
        {section.id, definition.application_key, Enum.map(section.scopes, &to_string/1)}
      end

    expected =
      for %{"key" => key, "owner" => owner, "scopes" => scopes} <- @golden,
          owner not in ["cadence", "console"],
          do: {key, owner, scopes}

    assert Enum.sort(declared) == Enum.sort(expected)
  end

  for {scope_name, mission?} <- [organization: false, mission: true] do
    test "Management.Settings lists exactly the golden's settings sections (#{scope_name})", c do
      mission_id = if unquote(mission?), do: c.mission_id

      assert {:ok, %{sections: sections}} =
               Settings.load(c.scope, mission_id, "cadence.governance")

      listed = Enum.map(sections, &{&1.id, owner(&1.owner)})

      assert Enum.sort(listed) ==
               Enum.sort(
                 for s <- golden(unquote(scope_name)),
                     s["owner"] != "console",
                     do: {s["key"], s["owner"]}
               )
    end

    test "the console shows every golden section (#{scope_name})", c do
      mission_id = if unquote(mission?), do: c.mission_id
      assert {:ok, %{sections: sections}} = ConsoleSettings.load(c.scope, mission_id)

      assert Enum.sort(Enum.map(sections, & &1.key)) ==
               Enum.sort(for s <- golden(unquote(scope_name)), do: s["key"])
    end
  end

  test "the golden's keys are unique" do
    keys = Enum.map(@golden, & &1["key"])
    assert keys == Enum.uniq(keys)
  end

  defp golden(scope), do: Enum.filter(@golden, &(to_string(scope) in &1["scopes"]))

  defp owner(%{kind: "host"}), do: "cadence"
  defp owner(%{kind: "application", applicationKey: key}), do: key
end
