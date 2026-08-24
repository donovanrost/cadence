defmodule CadenceWeb.Assets.CsvDownloadButtonTest do
  use ExUnit.Case, async: true

  test "CSV button preserves download behavior, fallback, cleanup, and accessibility" do
    app_root = Path.expand("../../..", __DIR__)
    script = Path.join(app_root, "assets/test/csv_download_button_test.mjs")

    assert {output, 0} = System.cmd("node", [script], cd: app_root, stderr_to_stdout: true)
    assert output =~ "csv_download_button_test passed"
  end
end
