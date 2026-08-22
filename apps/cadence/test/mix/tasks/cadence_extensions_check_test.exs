defmodule Mix.Tasks.Cadence.Extensions.CheckTest do
  use Cadence.UnitCase, async: false

  alias Mix.Tasks.Cadence.Extensions.Check

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn -> Mix.shell(previous_shell) end)

    :ok
  end

  test "validates and summarizes the complete compiled catalog" do
    Check.run([])

    assert_received {:mix_shell, :info, [summary]}
    assert summary =~ "Extension host integrity: 9 packages"
    assert summary =~ "4 applications (3 available)"
    assert summary =~ "5 capabilities"
    assert summary =~ "1 transport kind"
    assert summary =~ "1 provider connector"
    assert summary =~ "7 widget types"
    assert summary =~ "4 source adapters"
    assert summary =~ "2 catalog importers"
    assert summary =~ "action, preflight, status, surface, and reference providers valid"
  end

  test "rejects unexpected arguments" do
    assert_raise Mix.Error, ~r/Unexpected arguments/, fn ->
      Check.run(["--unknown"])
    end
  end
end
