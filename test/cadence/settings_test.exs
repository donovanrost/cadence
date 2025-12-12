defmodule Cadence.SettingsTest do
  use Cadence.DataCase, async: true

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures

  alias Cadence.Settings
  alias Cadence.Settings.Setting

  describe "definitions" do
    test "get_definition/2 returns definition for known settings" do
      definition = Settings.get_definition(:procedures, :required_approvals)

      assert definition.key == :required_approvals
      assert definition.type == :integer
      assert definition.default == 1
      assert definition.scope == :both
      assert definition.restrictiveness == :higher
    end

    test "get_definition/2 returns nil for unknown settings" do
      assert Settings.get_definition(:procedures, :unknown_setting) == nil
      assert Settings.get_definition(:unknown_namespace, :some_key) == nil
    end

    test "list_definitions/1 returns all settings for a namespace" do
      definitions = Settings.list_definitions(:procedures)

      assert length(definitions) == 3

      keys = Enum.map(definitions, & &1.key)
      assert :required_approvals in keys
      assert :allow_self_approval in keys
      assert :allow_withdrawal in keys
    end

    test "list_definitions/1 returns empty list for unknown namespace" do
      assert Settings.list_definitions(:unknown_namespace) == []
    end

    test "list_namespaces/0 returns all available namespaces" do
      namespaces = Settings.list_namespaces()
      assert :procedures in namespaces
    end
  end

  describe "get/3 - getting effective values" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "returns definition default when no setting stored", %{mission: mission} do
      assert Settings.get(mission, :procedures, :required_approvals) == 1
      assert Settings.get(mission, :procedures, :allow_self_approval) == true
      assert Settings.get(mission, :procedures, :allow_withdrawal) == true
    end

    test "returns org value when only org setting exists", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)

      mission = Cadence.Repo.preload(mission, :organization)
      assert Settings.get(mission, :procedures, :required_approvals) == 3
    end

    test "returns mission override when it exists", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 3)

      mission = Cadence.Repo.preload(mission, :organization)
      assert Settings.get(mission, :procedures, :required_approvals) == 3
    end

    test "returns nil for unknown settings", %{mission: mission} do
      assert Settings.get(mission, :procedures, :unknown) == nil
      assert Settings.get(mission, :unknown, :key) == nil
    end
  end

  describe "all/2 - getting all settings for a namespace" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "returns all settings with effective values", %{mission: mission} do
      all = Settings.all(mission, :procedures)

      assert all[:required_approvals] == 1
      assert all[:allow_self_approval] == true
      assert all[:allow_withdrawal] == true
    end

    test "returns org values when set", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 5)

      mission = Cadence.Repo.preload(mission, :organization)
      all = Settings.all(mission, :procedures)

      assert all[:required_approvals] == 5
    end
  end

  describe "get_org/3 - getting org-level values" do
    test "returns definition default when not stored" do
      org = organization_fixture()
      assert Settings.get_org(org, :procedures, :required_approvals) == 1
    end

    test "returns stored value when set" do
      org = organization_fixture()
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 4)

      assert Settings.get_org(org, :procedures, :required_approvals) == 4
    end
  end

  describe "get_mission_override/3" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "returns nil when no override exists", %{mission: mission} do
      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == nil
    end

    test "returns override value when set", %{mission: mission} do
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 3)

      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 3
    end
  end

  describe "set_org/4 - setting org-level values" do
    test "creates setting when it doesn't exist" do
      org = organization_fixture()

      assert {:ok, %Setting{} = setting} =
               Settings.set_org(org, :procedures, :required_approvals, 2)

      assert setting.scope_type == "organization"
      assert setting.scope_id == org.id
      assert setting.namespace == "procedures"
      assert setting.key == "required_approvals"
      assert Setting.extract_value(setting.value) == 2
    end

    test "updates setting when it already exists" do
      org = organization_fixture()

      {:ok, setting1} = Settings.set_org(org, :procedures, :required_approvals, 2)
      {:ok, setting2} = Settings.set_org(org, :procedures, :required_approvals, 3)

      assert setting1.id == setting2.id
      assert Setting.extract_value(setting2.value) == 3
    end

    test "validates value against definition" do
      org = organization_fixture()

      # required_approvals must be 1-10
      assert {:error, :invalid_value} =
               Settings.set_org(org, :procedures, :required_approvals, 0)

      assert {:error, :invalid_value} =
               Settings.set_org(org, :procedures, :required_approvals, 11)

      # Type validation
      assert {:error, :invalid_value} =
               Settings.set_org(org, :procedures, :required_approvals, "not an integer")
    end

    test "returns error for unknown settings" do
      org = organization_fixture()

      assert {:error, :unknown_setting} =
               Settings.set_org(org, :procedures, :unknown_key, 1)
    end
  end

  describe "set_mission/4 - setting mission-level overrides" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "creates override when value is valid", %{mission: mission} do
      assert {:ok, %Setting{} = setting} =
               Settings.set_mission(mission, :procedures, :required_approvals, 2)

      assert setting.scope_type == "mission"
      assert setting.scope_id == mission.id
    end

    test "validates value against definition", %{mission: mission} do
      assert {:error, :invalid_value} =
               Settings.set_mission(mission, :procedures, :required_approvals, 0)

      assert {:error, :invalid_value} =
               Settings.set_mission(mission, :procedures, :required_approvals, 11)
    end

    test "returns error for unknown settings", %{mission: mission} do
      assert {:error, :unknown_setting} =
               Settings.set_mission(mission, :procedures, :unknown_key, 1)
    end
  end

  describe "restrictiveness - :higher (mission value must be >= org value)" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)
      %{org: org, mission: mission}
    end

    test "allows mission to set higher value", %{mission: mission} do
      assert {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 3)
    end

    test "allows mission to set equal value", %{mission: mission} do
      assert {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 2)
    end

    test "rejects mission setting lower value", %{mission: mission} do
      assert {:error, :less_restrictive_than_org, details} =
               Settings.set_mission(mission, :procedures, :required_approvals, 1)

      assert details.org_value == 2
      assert details.min_allowed == 2
    end
  end

  describe "restrictiveness - :false_is_stricter (false is more restrictive than true)" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "allows mission to set false when org is true", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, true)

      assert {:ok, _} = Settings.set_mission(mission, :procedures, :allow_self_approval, false)
    end

    test "allows mission to set false when org is false", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      assert {:ok, _} = Settings.set_mission(mission, :procedures, :allow_self_approval, false)
    end

    test "rejects mission setting true when org is false", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      assert {:error, :less_restrictive_than_org, details} =
               Settings.set_mission(mission, :procedures, :allow_self_approval, true)

      assert details.org_value == false
      assert details.reason == "cannot enable when disabled at org level"
    end

    test "allows mission to set true when org is true", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, true)

      assert {:ok, _} = Settings.set_mission(mission, :procedures, :allow_self_approval, true)
    end
  end

  describe "allow_withdrawal - :false_is_stricter" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "allows mission to set false when org is true", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, true)

      assert {:ok, _} = Settings.set_mission(mission, :procedures, :allow_withdrawal, false)
    end

    test "rejects mission setting true when org is false", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, false)

      assert {:error, :less_restrictive_than_org, details} =
               Settings.set_mission(mission, :procedures, :allow_withdrawal, true)

      assert details.org_value == false
      assert details.reason == "cannot enable when disabled at org level"
    end

    test "allows mission to set true when org is true", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, true)

      assert {:ok, _} = Settings.set_mission(mission, :procedures, :allow_withdrawal, true)
    end
  end

  describe "can_mission_override?/4" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)
      %{org: org, mission: mission}
    end

    test "returns :ok for valid override", %{mission: mission} do
      assert :ok = Settings.can_mission_override?(mission, :procedures, :required_approvals, 3)
    end

    test "returns error for invalid override", %{mission: mission} do
      assert {:error, :less_restrictive_than_org, _} =
               Settings.can_mission_override?(mission, :procedures, :required_approvals, 1)
    end
  end

  describe "clear_mission_override/3" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 3)
      %{org: org, mission: mission}
    end

    test "removes the mission override", %{mission: mission} do
      assert :ok = Settings.clear_mission_override(mission, :procedures, :required_approvals)

      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == nil
    end

    test "returns error when no override exists", %{mission: mission} do
      # First clear it
      Settings.clear_mission_override(mission, :procedures, :required_approvals)

      # Then try again
      assert {:error, :not_found} =
               Settings.clear_mission_override(mission, :procedures, :required_approvals)
    end
  end

  describe "get_all_org_settings/2" do
    test "returns all settings with values and metadata" do
      org = organization_fixture()
      settings = Settings.get_all_org_settings(org, :procedures)

      assert length(settings) == 3

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      assert approvals.label == "Required Approvals"
      assert approvals.value == 1
      assert approvals.type == :integer
      assert approvals.restrictiveness == :higher
    end

    test "returns stored org values instead of defaults" do
      org = organization_fixture()
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 5)

      settings = Settings.get_all_org_settings(org, :procedures)

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      assert approvals.value == 5
      assert approvals.default == 1
    end

    test "includes description and validate fields" do
      org = organization_fixture()
      settings = Settings.get_all_org_settings(org, :procedures)

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      assert approvals.description != nil
      assert approvals.validate == {:range, 1, 10}
    end
  end

  describe "get_all_mission_settings/2" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      %{org: org, mission: mission}
    end

    test "returns settings with override info", %{mission: mission} do
      settings = Settings.get_all_mission_settings(mission, :procedures)

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      assert approvals.org_value == 1
      assert approvals.has_override == false
      assert approvals.min_value == 1
    end

    test "shows mission override when set", %{mission: mission} do
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 3)

      settings = Settings.get_all_mission_settings(mission, :procedures)

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      assert approvals.org_value == 1
      assert approvals.mission_override == 3
      assert approvals.has_override == true
      assert approvals.effective_value == 3
    end

    test "computes effective_value from org when no override", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 4)

      settings = Settings.get_all_mission_settings(mission, :procedures)

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      assert approvals.org_value == 4
      assert approvals.effective_value == 4
      assert approvals.has_override == false
    end

    test "computes can_override for false_is_stricter when org allows", %{mission: mission} do
      # By default, org allows self-approval (true)
      settings = Settings.get_all_mission_settings(mission, :procedures)
      self_approval = Enum.find(settings, &(&1.key == :allow_self_approval))
      assert self_approval.can_override == true
    end

    test "computes can_override for false_is_stricter when org disables", %{
      org: org,
      mission: mission
    } do
      # When org disables self-approval
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      settings = Settings.get_all_mission_settings(mission, :procedures)
      self_approval = Enum.find(settings, &(&1.key == :allow_self_approval))
      assert self_approval.can_override == false
    end

    test "computes min_value for higher restrictiveness", %{org: org, mission: mission} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)

      settings = Settings.get_all_mission_settings(mission, :procedures)

      approvals = Enum.find(settings, &(&1.key == :required_approvals))
      # min_value should be org value (3) since restrictiveness is :higher
      assert approvals.min_value == 3
      # max_value should be the range max (10)
      assert approvals.max_value == 10
    end
  end

  describe "get_namespace_info/1" do
    test "returns info for procedures namespace" do
      info = Settings.get_namespace_info(:procedures)

      assert info.key == :procedures
      assert info.label == "Procedures"
      assert info.description == "Settings for procedure approval workflows"
      assert info.icon == "hero-document-text"
    end

    test "returns nil for unknown namespace" do
      assert Settings.get_namespace_info(:unknown) == nil
    end
  end

  describe "list_namespaces_with_info/0" do
    test "returns all namespaces with their display info" do
      namespaces = Settings.list_namespaces_with_info()

      assert length(namespaces) >= 1
      assert Enum.any?(namespaces, &(&1.key == :procedures))
    end

    test "excludes namespaces without info" do
      namespaces = Settings.list_namespaces_with_info()

      # All returned namespaces should have required fields
      for ns <- namespaces do
        assert Map.has_key?(ns, :key)
        assert Map.has_key?(ns, :label)
        assert Map.has_key?(ns, :description)
      end
    end
  end

  describe "Setting schema" do
    test "wrap_value/2 creates properly formatted value" do
      assert Setting.wrap_value(42, :integer) == %{"type" => "integer", "value" => 42}
      assert Setting.wrap_value(true, :boolean) == %{"type" => "boolean", "value" => true}
      assert Setting.wrap_value("test", :string) == %{"type" => "string", "value" => "test"}
    end

    test "extract_value/1 extracts the value from wrapped format" do
      assert Setting.extract_value(%{"type" => "integer", "value" => 42}) == 42
      assert Setting.extract_value(%{"type" => "boolean", "value" => true}) == true
      assert Setting.extract_value(%{}) == nil
    end

    test "changeset validates value structure" do
      attrs = %{
        scope_type: "organization",
        scope_id: Ecto.UUID.generate(),
        namespace: "procedures",
        key: "test",
        value: %{"missing" => "type"}
      }

      changeset = Setting.changeset(%Setting{}, attrs)
      refute changeset.valid?
      assert {"must have a 'type' key", _} = changeset.errors[:value]
    end

    test "changeset validates scope_type" do
      attrs = %{
        scope_type: "invalid",
        scope_id: Ecto.UUID.generate(),
        namespace: "procedures",
        key: "test",
        value: Setting.wrap_value(1, :integer)
      }

      changeset = Setting.changeset(%Setting{}, attrs)
      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:scope_type]
    end
  end
end
