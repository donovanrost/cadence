defmodule CCSDS.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/donovanrost/cadence"

  def project do
    [
      app: :ccsds,
      name: "CCSDS",
      workspace: workspace(),
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Dependency-free CCSDS protocol data types, wire codecs, and pure state machines"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ["lib", ".formatter.exs", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url,
      source_ref: "ccsds-v#{@version}",
      groups_for_modules: [
        Packets: [CCSDS.Packet, CCSDS.SpacePacket, CCSDS.EncapsulationPacket],
        "Space Data Link Protocols": [CCSDS.SDLP.FrameCodec, CCSDS.SDLP.Segmentation],
        "Telecommand and COP-1": [CCSDS.TC.FrameCodec, CCSDS.Transport.COP1.FOP],
        "File Delivery": [CCSDS.CFDP],
        "Space Data Link Security": [CCSDS.SDLS.Provider],
        "Time Codes": [CCSDS.Time.CDS, CCSDS.Time.CUC],
        "Channel Coding": [CCSDS.ChannelCoding.BCH, CCSDS.ChannelCoding.LDPC]
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
