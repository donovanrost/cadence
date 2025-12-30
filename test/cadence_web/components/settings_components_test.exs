defmodule CadenceWeb.SettingsComponentsTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import CadenceWeb.SettingsComponents

  defp assert_selector(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> case do
      [] -> flunk("Expected selector #{inspect(selector)} to match")
      _ -> :ok
    end
  end

  defp refute_selector(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> case do
      [] -> :ok
      _ -> flunk("Expected selector #{inspect(selector)} to be empty")
    end
  end

  defp assert_selector_text(html, selector, text) do
    content =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.text()

    if String.contains?(content, text) do
      :ok
    else
      flunk("Expected selector #{inspect(selector)} to include #{inspect(text)}")
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

      assert_selector_text(html, "div", "Test Setting")
      assert_selector_text(html, "p", "A test description")
      assert_selector_text(html, "span", "Helpful hint")
      assert_selector(html, ~s(input[type="text"]))
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

      assert_selector_text(html, "div", "Test Setting")
      assert_selector_text(html, "p", "A test description")
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

      assert_selector_text(html, "span", "Invalid value")
      assert_selector(html, ".text-error")
    end
  end

  describe "setting_number_input/1" do
    test "renders with value and constraints" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={5} min={1} max={10} name="test" />
        """)

      assert_selector(html, ~s(input[type="number"][name="test"][value="5"]))
      assert_selector(html, ~s(input[type="number"][name="test"][min="1"][max="10"]))
    end

    test "renders without min/max when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={5} name="test" />
        """)

      assert_selector(html, ~s(input[type="number"][name="test"][value="5"]))
    end

    test "renders with increment/decrement buttons" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={5} min={1} max={10} name="test" />
        """)

      assert_selector(html, ~S(button[phx-click="increment_setting"][phx-value-name="test"]))
      assert_selector(html, ~S(button[phx-click="decrement_setting"][phx-value-name="test"]))
    end

    test "renders disabled decrement button at minimum" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_number_input value={1} min={1} max={10} name="test" />
        """)

      assert_selector(html, ~S(button[phx-click="decrement_setting"][disabled]))
    end
  end

  describe "setting_toggle/1" do
    test "renders enabled state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={true} name="test" />
        """)

      assert_selector(html, ~s(input[type="checkbox"][name="test"][checked]))
      assert_selector_text(html, "span", "Enabled")
    end

    test "renders disabled state" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={false} name="test" />
        """)

      refute_selector(html, ~s(input[type="checkbox"][name="test"][checked]))
      assert_selector_text(html, "span", "Disabled")
    end

    test "renders custom labels" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={true} name="test" enabled_label="Yes" disabled_label="No" />
        """)

      assert_selector_text(html, "span", "Yes")
    end

    test "includes hidden field for false value" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.setting_toggle value={true} name="test" />
        """)

      assert_selector(html, ~s(input[type="hidden"][name="test"][value="false"]))
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

      assert_selector_text(html, "span", "Organization default:")
      assert_selector_text(html, "span", "1")
      # Input should always be visible now
      assert_selector(html, ~s(input[type="number"][name="test"]))
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

      assert_selector(html, ~s(input[type="number"][name="test"][value="3"]))
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

      assert_selector_text(html, "span", "Must be at least 2")
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

      assert_selector_text(html, "span", "Must be at most 5")
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

      assert_selector(html, ~s(input.toggle[type="checkbox"][name="test"]))
      assert_selector_text(html, "span", "Organization default:")
      # Org value
      assert_selector_text(html, "span", "Enabled")
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

      assert_selector_text(html, "span", "Must be at least 2")
      assert_selector(html, ".text-error")
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
      assert_selector(html, ~s(input[type="checkbox"][name="test"][disabled]))
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
      assert_selector_text(html, "span", "Locked by organization policy")
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

      assert_selector_text(html, "h2", "My Section")
      assert_selector_text(html, "p", "Section content")
    end

    test "renders description when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.settings_section title="My Section" description="A helpful description">
          <p>Content</p>
        </.settings_section>
        """)

      assert_selector_text(html, "h2", "My Section")
      assert_selector_text(html, "p", "A helpful description")
    end
  end
end
