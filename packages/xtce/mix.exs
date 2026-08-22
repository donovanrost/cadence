defmodule XTCE.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/donovanrost/cadence"

  def project do
    [
      app: :xtce,
      name: "XTCE",
      workspace: workspace(),
      version: @version,
      elixir: "~> 1.15",
      description: description(),
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :xmerl]
    ]
  end

  defp description do
    "Bounded parser and offline schema validator for OMG XTCE 1.3 documents"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "XTCE specification" => "https://www.omg.org/spec/XTCE/1.3"
      },
      files: [
        "lib",
        "priv/xtce_1_3",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md"],
      source_url: @source_url,
      source_ref: "xtce-v#{@version}",
      groups_for_modules: [
        "Document model": [XTCE.Document, XTCE.Element],
        "Parsing and validation": [XTCE.Parser, XTCE.SchemaValidator]
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp workspace do
    [
      tags: [{:layer, :foundation}],
      affected_by: ["../../mix.exs", "../../.workspace.exs"]
    ]
  end
end
