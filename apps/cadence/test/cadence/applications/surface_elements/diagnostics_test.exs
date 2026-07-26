defmodule Cadence.Applications.SurfaceElements.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.SurfaceElements.{Diagnostic, Diagnostics}

  test "accepts a bounded block of uniquely identified exceptional findings" do
    diagnostics =
      diagnostics([
        %Diagnostic{
          id: "compiler-warning",
          code: "compiler.selector_narrowed",
          severity: :warning,
          title: "Selector narrowed",
          detail: "The selector excludes some packet variants.",
          value: "packets / HEALTH"
        }
      ])

    assert :ok = Diagnostics.validate(diagnostics)
  end

  test "rejects duplicate item identities" do
    item = diagnostic("duplicate")

    assert {:error, :invalid_application_surface_diagnostics} =
             Diagnostics.validate(diagnostics([item, item]))
  end

  test "rejects blocks larger than the host rendering bound" do
    items = Enum.map(1..21, &diagnostic("finding-#{&1}"))

    assert {:error, :invalid_application_surface_diagnostics} =
             Diagnostics.validate(diagnostics(items))
  end

  test "requires total count to include every rendered finding" do
    diagnostics = %Diagnostics{
      id: "application-diagnostics",
      title: "Application findings",
      items: [diagnostic("finding")],
      total_count: 0
    }

    assert {:error, :invalid_application_surface_diagnostics} =
             Diagnostics.validate(diagnostics)
  end

  defp diagnostics(items) do
    %Diagnostics{
      id: "application-diagnostics",
      title: "Application findings",
      items: items,
      total_count: length(items)
    }
  end

  defp diagnostic(id) do
    %Diagnostic{
      id: id,
      code: "application.finding",
      severity: :info,
      title: "Application finding",
      detail: "The application reported an exceptional condition."
    }
  end
end
