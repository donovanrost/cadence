defmodule CadenceWeb.LiveVueClipboardTestSupportTest do
  use ExUnit.Case, async: true
  use CadenceWeb, :html

  import CadenceWeb.LiveVueClipboardTestSupport
  import Phoenix.LiveViewTest, only: [render_component: 2]

  test "asserts ClipboardButton identity, clipboard text, data attrs, and SSR contract" do
    html = render_clipboard_button()

    clipboard_button =
      assert_clipboard_button(
        html,
        ~s(#copy-route[phx-hook="ClipboardButton"][data-clipboard-text*="panel=evidence"][data-contract="route"])
      )

    assert clipboard_button.props["label"] == "Copy route"
    assert clipboard_text(html, "#copy-route") == "/ops/dashboard?panel=evidence"

    refute_clipboard_button(
      html,
      ~s(#copy-route[data-clipboard-text*="selected_target="])
    )
  end

  test "fails closed for malformed selectors and mismatched host contracts" do
    html = render_clipboard_button()

    assert_raise ArgumentError, fn ->
      assert_clipboard_button(html, ~s(#copy-route[data-clipboard-text*="panel=evidence"))
    end

    assert catch_error(assert_clipboard_button(html, "#missing-route"))

    assert catch_error(
             assert_clipboard_button(
               html,
               ~s(#copy-route[data-clipboard-text*="panel=data_link"])
             )
           )

    assert catch_error(
             render_mismatched_clipboard_button(component: "OtherButton")
             |> assert_clipboard_button("#copy-route")
           )

    assert catch_error(
             render_mismatched_clipboard_button(button_id: "other-route")
             |> assert_clipboard_button("#copy-route")
           )
  end

  defp render_clipboard_button do
    render_component(&clipboard_button/1,
      component: "ClipboardButton",
      button_id: "copy-route"
    )
  end

  defp render_mismatched_clipboard_button(overrides) do
    render_component(
      &clipboard_button/1,
      Keyword.merge(
        [component: "ClipboardButton", button_id: "copy-route"],
        overrides
      )
    )
  end

  defp clipboard_button(assigns) do
    ~H"""
    <.vue
      id="copy-route-component"
      v-component={@component}
      button_id={@button_id}
      clipboard_text="/ops/dashboard?panel=evidence"
      data_attrs={%{"data-contract" => "route"}}
      label="Copy route"
      v-ssr={false}
    />
    """
  end
end
