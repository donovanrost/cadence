defmodule CadenceWeb.Assets.ClipboardButtonTest do
  use ExUnit.Case, async: true

  test "clipboard button preserves payload resolution, fallbacks, feedback, accessibility, and cleanup" do
    app_root = Path.expand("../../..", __DIR__)
    script = Path.join(app_root, "assets/test/clipboard_button_test.mjs")

    assert {output, 0} = System.cmd("node", [script], cd: app_root, stderr_to_stdout: true)
    assert output =~ "clipboard_button_test passed"
  end
end
