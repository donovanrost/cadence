defmodule Cadence.Architecture.DependencyBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.DependencyBoundary

  test "finds internal root-facade and non-persistence schema dependencies" do
    graph = %{
      "lib/cadence/dashboards/source.ex" => %{
        "lib/cadence.ex" => "runtime",
        "lib/cadence/persistence/schemas/dashboard_row.ex" => "export"
      },
      "lib/cadence/persistence.ex" => %{
        "lib/cadence/persistence/schemas/dashboard_row.ex" => "runtime"
      },
      "lib/cadence/persistence/store.ex" => %{
        "lib/cadence/persistence/schemas/dashboard_row.ex" => "runtime"
      }
    }

    assert [
             %{
               kind: :persistence_schema,
               source: "lib/cadence/dashboards/source.ex",
               label: "export"
             },
             %{
               kind: :root_facade,
               source: "lib/cadence/dashboards/source.ex",
               label: "runtime"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "compares current edges with the checked-in debt baseline" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence/dashboards/source.ex" => %{"lib/cadence.ex" => "runtime"}
      })

    [finding] = findings

    baseline = %{
      owner: "Core architecture",
      review_by: ~D[2026-10-18],
      rationale: "Retire transitional edges",
      allowed: MapSet.new([finding.fingerprint, "root_facade|resolved|edge"])
    }

    assert %{
             new: [],
             resolved: ["root_facade|resolved|edge"],
             expired?: false
           } = DependencyBoundary.compare(findings, baseline, ~D[2026-07-18])

    assert %{expired?: true} =
             DependencyBoundary.compare(findings, baseline, ~D[2026-10-19])
  end

  test "reports an edge missing from the baseline" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence/dashboards/source.ex" => %{"lib/cadence.ex" => "runtime"}
      })

    baseline = %{
      owner: "Core architecture",
      review_by: ~D[2026-10-18],
      rationale: "Retire transitional edges",
      allowed: MapSet.new()
    }

    assert %{new: [%{kind: :root_facade}], resolved: []} =
             DependencyBoundary.compare(findings, baseline, ~D[2026-07-18])
  end

  test "loads required ownership and expiry metadata" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cadence-dependency-baseline-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.write!(path, """
    # owner: Core architecture
    # review-by: 2026-10-18
    # rationale: Remove transitional dependencies

    root_facade|lib/cadence/source.ex|lib/cadence.ex
    """)

    on_exit(fn -> File.rm!(path) end)

    assert %{
             owner: "Core architecture",
             review_by: ~D[2026-10-18],
             rationale: "Remove transitional dependencies",
             allowed: allowed
           } = DependencyBoundary.read_baseline!(path)

    assert MapSet.member?(
             allowed,
             "root_facade|lib/cadence/source.ex|lib/cadence.ex"
           )
  end
end
