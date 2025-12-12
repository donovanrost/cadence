defmodule CadenceWeb.SettingsComponentsTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import CadenceWeb.SettingsComponents

  describe "setting_card/1" do
    test "renders label, description, and hint" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_card
          label="Test Setting"
          description="A test description"
          hint="Helpful hint"
        >
          <input type="text" />
        </.setting_card>
        """)

      assert html =~ "Test Setting"
      assert html =~ "A test description"
      assert html =~ "Helpful hint"
      assert html =~ ~s(type="text")
    end

    test "renders without hint when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_card
          label="Test Setting"
          description="A test description"
        >
          <input type="text" />
        </.setting_card>
        """)

      assert html =~ "Test Setting"
      assert html =~ "A test description"
    end

    test "renders error state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_card
          label="Test Setting"
          description="Description"
          error="Invalid value"
        >
          <input type="text" />
        </.setting_card>
        """)

      assert html =~ "Invalid value"
      assert html =~ "text-error"
    end
  end

  describe "setting_number_input/1" do
    test "renders with value and constraints" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={5} min={1} max={10} name="test" />
        """)

      assert html =~ ~s(value="5")
      assert html =~ ~s(min="1")
      assert html =~ ~s(max="10")
      assert html =~ ~s(name="test")
      assert html =~ ~s(type="number")
    end

    test "renders without min/max when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={5} name="test" />
        """)

      assert html =~ ~s(value="5")
    end

    test "renders with increment/decrement buttons" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={5} min={1} max={10} name="test" />
        """)

      assert html =~ "increment_setting"
      assert html =~ "decrement_setting"
    end

    test "renders disabled decrement button at minimum" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={1} min={1} max={10} name="test" />
        """)

      assert html =~ "disabled"
    end
  end

  describe "setting_toggle/1" do
    test "renders enabled state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={true} name="test" />
        """)

      assert html =~ "checked"
      assert html =~ "Enabled"
      assert html =~ ~s(name="test")
    end

    test "renders disabled state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={false} name="test" />
        """)

      refute html =~ "checked"
      assert html =~ "Disabled"
    end

    test "renders custom labels" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={true} name="test" enabled_label="Yes" disabled_label="No" />
        """)

      assert html =~ "Yes"
    end

    test "includes hidden field for false value" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={true} name="test" />
        """)

      assert html =~ ~s(type="hidden")
      assert html =~ ~s(value="false")
    end
  end

  describe "setting_override_card/1" do
    test "shows org default and input" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={1}
          effective_value={1}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
          can_override={true}
        />
        """)

      assert html =~ "Organization default"
      assert html =~ "1"
      # Input should always be visible now
      assert html =~ ~s(type="number")
    end

    test "shows effective value in input" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={1}
          effective_value={3}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
          can_override={true}
        />
        """)

      assert html =~ ~s(type="number")
      assert html =~ ~s(value="3")
    end

    test "shows restrictiveness hint for :higher" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={2}
          effective_value={3}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
          can_override={true}
        />
        """)

      assert html =~ "Must be at least 2"
    end

    test "shows restrictiveness hint for :lower" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={5}
          effective_value={3}
          min_value={1}
          max_value={10}
          restrictiveness={:lower}
          name="test"
          can_override={true}
        />
        """)

      assert html =~ "Must be at most 5"
    end

    test "renders boolean toggle when type is boolean" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:boolean}
          org_value={true}
          effective_value={false}
          restrictiveness={:false_is_stricter}
          name="test"
          can_override={true}
        />
        """)

      assert html =~ "toggle"
      assert html =~ "Organization default"
      assert html =~ "Enabled"  # Org value
    end

    test "shows error message when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={2}
          effective_value={1}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
          error="Must be at least 2"
          can_override={true}
        />
        """)

      assert html =~ "Must be at least 2"
      assert html =~ "text-error"
    end

    test "disables toggle when can_override is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:boolean}
          org_value={false}
          effective_value={false}
          restrictiveness={:false_is_stricter}
          name="test"
          can_override={false}
        />
        """)

      # Toggle should be disabled when can_override is false
      assert html =~ "disabled"
    end

    test "shows locked message when org disables a :false_is_stricter boolean" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:boolean}
          org_value={false}
          effective_value={false}
          restrictiveness={:false_is_stricter}
          name="test"
          can_override={false}
        />
        """)

      # Should show locked indicator
      assert html =~ "Locked by organization policy"
    end
  end

  describe "settings_section/1" do
    test "renders title and content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_section title="My Section">
          <p>Section content</p>
        </.settings_section>
        """)

      assert html =~ "My Section"
      assert html =~ "Section content"
    end

    test "renders description when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_section title="My Section" description="A helpful description">
          <p>Content</p>
        </.settings_section>
        """)

      assert html =~ "My Section"
      assert html =~ "A helpful description"
    end
  end
end
