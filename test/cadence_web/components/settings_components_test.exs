defmodule CadenceWeb.SettingsComponentsTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import CadenceWeb.SettingsComponents

  describe "settings_layout/1" do
    test "renders tabs and content slots" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_layout>
          <:tabs>
            <.settings_tab patch="/settings" active={true} icon="hero-cog-6-tooth">
              General
            </.settings_tab>
          </:tabs>
          <:content>
            <p>Content here</p>
          </:content>
        </.settings_layout>
        """)

      assert html =~ "General"
      assert html =~ "Content here"
      assert html =~ "hero-cog-6-tooth"
    end

    test "renders multiple tabs" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_layout>
          <:tabs>
            <.settings_tab patch="/settings" active={true} icon="hero-cog-6-tooth">
              General
            </.settings_tab>
            <.settings_tab patch="/settings/procedures" active={false} icon="hero-clipboard-document-list">
              Procedures
            </.settings_tab>
          </:tabs>
          <:content>
            <p>Tab content</p>
          </:content>
        </.settings_layout>
        """)

      assert html =~ "General"
      assert html =~ "Procedures"
      assert html =~ "hero-clipboard-document-list"
    end
  end

  describe "settings_tab/1" do
    test "renders active state correctly" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_tab patch="/settings" active={true} icon="hero-cog-6-tooth">
          Active Tab
        </.settings_tab>
        """)

      # Active state uses bg-primary/10 in resolved implementation
      assert html =~ "bg-primary"
      assert html =~ "Active Tab"
      assert html =~ ~s(href="/settings")
    end

    test "renders inactive state correctly" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_tab patch="/settings" active={false} icon="hero-cog-6-tooth">
          Inactive Tab
        </.settings_tab>
        """)

      # Inactive state should not have bg-primary/10
      assert html =~ "Inactive Tab"
      assert html =~ "hover:bg-base-300"
    end

    test "renders icon" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_tab patch="/settings" active={false} icon="hero-cog-6-tooth">
          Tab
        </.settings_tab>
        """)

      assert html =~ "hero-cog-6-tooth"
    end
  end

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
    test "shows org default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={1}
          mission_override={nil}
          has_override={false}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
        />
        """)

      assert html =~ "Organization default"
      assert html =~ "1"
      assert html =~ "Override for this mission"
    end

    test "shows input when override enabled" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:integer}
          org_value={1}
          mission_override={3}
          has_override={true}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
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
          mission_override={3}
          has_override={true}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
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
          mission_override={3}
          has_override={true}
          min_value={1}
          max_value={10}
          restrictiveness={:lower}
          name="test"
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
          mission_override={false}
          has_override={true}
          restrictiveness={:false_is_stricter}
          name="test"
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
          mission_override={1}
          has_override={true}
          min_value={1}
          max_value={10}
          restrictiveness={:higher}
          name="test"
          error="Must be at least 2"
        />
        """)

      assert html =~ "Must be at least 2"
      assert html =~ "text-error"
    end

    test "disables override when org has false for :false_is_stricter" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_override_card
          label="Test"
          description="Desc"
          type={:boolean}
          org_value={false}
          mission_override={nil}
          has_override={false}
          restrictiveness={:false_is_stricter}
          name="test"
        />
        """)

      # Should show that override cannot be enabled
      assert html =~ "disabled" or html =~ "Disabled at organization level"
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
