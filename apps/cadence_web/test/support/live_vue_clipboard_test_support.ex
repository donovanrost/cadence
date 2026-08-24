defmodule CadenceWeb.LiveVueClipboardTestSupport do
  @moduledoc false

  import ExUnit.Assertions

  @clipboard_component "ClipboardButton"
  @selector_pattern ~r/\A#(?<button_id>[A-Za-z][A-Za-z0-9_-]*)(?<attributes>(?:\[[A-Za-z][A-Za-z0-9_-]*(?:\*=|=)"[^"]*"\])*)\z/
  @attribute_pattern ~r/\[(?<name>[A-Za-z][A-Za-z0-9_-]*)(?<operator>\*=|=)"(?<value>[^"]*)"\]/

  def assert_clipboard_button(renderable, selector) do
    {button_id, attributes} = parse_selector!(selector)
    clipboard_button = clipboard_button!(renderable, button_id)

    Enum.each(attributes, &assert_selector_attribute!(clipboard_button, &1))

    clipboard_button
  end

  def refute_clipboard_button(renderable, selector) do
    {button_id, attributes} = parse_selector!(selector)
    clipboard_button = clipboard_button!(renderable, button_id)

    assert attributes != []
    Enum.each(attributes, &refute_selector_attribute!(clipboard_button, &1))

    clipboard_button
  end

  def clipboard_text(renderable, selector) do
    renderable
    |> assert_clipboard_button(selector)
    |> clipboard_text_prop!()
  end

  defp clipboard_button!(renderable, button_id) do
    clipboard_button = clipboard_button_component(renderable, button_id)

    assert clipboard_button.component == @clipboard_component
    assert clipboard_button.props["button_id"] == button_id
    refute clipboard_button.ssr

    clipboard_text_prop!(clipboard_button)
    clipboard_button
  end

  defp clipboard_button_component(renderable, "dashboard-data-link-copy-link" = button_id) do
    panel = LiveVue.Test.get_vue(renderable, id: "dashboard-data-link-inspector-component")

    assert panel.component == "DataLinkInspectorPanel"
    refute panel.ssr

    clipboard = get_in(panel.props, ["presentation", "clipboard"])
    assert clipboard["button_id"] == button_id

    %{
      component: @clipboard_component,
      props: clipboard,
      ssr: false
    }
  end

  defp clipboard_button_component(renderable, button_id) do
    LiveVue.Test.get_vue(renderable, id: button_id <> "-component")
  rescue
    RuntimeError -> nested_evidence_clipboard_button!(renderable, button_id)
  end

  defp nested_evidence_clipboard_button!(renderable, "dashboard-evidence-copy-link" = button_id) do
    parent = LiveVue.Test.get_vue(renderable, id: "dashboard-evidence-inspector-component")

    assert parent.component == "EvidenceInspectorPanel"
    assert parent.ssr == false

    copy = get_in(parent.props, ["presentation", "actions", "copy"])
    assert copy["props"]["button_id"] == button_id
    assert copy["host"]["attrs"]["data-name"] == @clipboard_component

    %{
      component: @clipboard_component,
      id: copy["host"]["attrs"]["id"],
      class: copy["host"]["attrs"]["class"],
      props: copy["props"],
      ssr: false
    }
  end

  defp nested_evidence_clipboard_button!(_renderable, button_id) do
    raise RuntimeError, ~s(No Vue component found with id="#{button_id}-component")
  end

  defp clipboard_text_prop!(clipboard_button) do
    assert {:ok, clipboard_text} = Map.fetch(clipboard_button.props, "clipboard_text")
    assert is_binary(clipboard_text)
    clipboard_text
  end

  defp assert_selector_attribute!(clipboard_button, %{
         "name" => "data-clipboard-text",
         "operator" => operator,
         "value" => expected
       }) do
    assert_attribute!(clipboard_text_prop!(clipboard_button), operator, expected)
  end

  defp assert_selector_attribute!(clipboard_button, %{
         "name" => "phx-hook",
         "operator" => "=",
         "value" => expected
       }) do
    assert clipboard_button.component == expected
  end

  defp assert_selector_attribute!(clipboard_button, %{
         "name" => "data-" <> _ = name,
         "operator" => operator,
         "value" => expected
       }) do
    assert {:ok, data_attrs} = Map.fetch(clipboard_button.props, "data_attrs")
    assert is_map(data_attrs)
    assert {:ok, actual} = Map.fetch(data_attrs, name)
    assert_attribute!(actual, operator, expected)
  end

  defp assert_selector_attribute!(_clipboard_button, attribute) do
    raise ArgumentError,
          "unsupported ClipboardButton selector attribute: #{inspect(attribute)}"
  end

  defp refute_selector_attribute!(clipboard_button, %{
         "name" => "data-clipboard-text",
         "operator" => operator,
         "value" => unexpected
       }) do
    refute_attribute!(clipboard_text_prop!(clipboard_button), operator, unexpected)
  end

  defp refute_selector_attribute!(_clipboard_button, attribute) do
    raise ArgumentError,
          "unsupported negated ClipboardButton selector attribute: #{inspect(attribute)}"
  end

  defp assert_attribute!(actual, "=", expected), do: assert(actual == expected)
  defp assert_attribute!(actual, "*=", expected), do: assert(actual =~ expected)
  defp refute_attribute!(actual, "=", unexpected), do: refute(actual == unexpected)
  defp refute_attribute!(actual, "*=", unexpected), do: refute(actual =~ unexpected)

  defp parse_selector!(selector) when is_binary(selector) do
    case Regex.named_captures(@selector_pattern, selector) do
      %{"button_id" => button_id, "attributes" => attributes} ->
        parsed_attributes =
          Enum.map(Regex.scan(@attribute_pattern, attributes), fn [_, name, operator, value] ->
            %{"name" => name, "operator" => operator, "value" => value}
          end)

        {button_id, parsed_attributes}

      nil ->
        raise ArgumentError, "malformed ClipboardButton selector: #{inspect(selector)}"
    end
  end

  defp parse_selector!(selector) do
    raise ArgumentError, "malformed ClipboardButton selector: #{inspect(selector)}"
  end
end
