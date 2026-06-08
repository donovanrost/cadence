defmodule CadenceWeb.SpacecraftTypeApplications do
  @moduledoc """
  Small registry of platform applications exposed in the New Spacecraft Profile
  form. Per the agreed UX, the form only declares which applications are
  enabled for a profile; per-app configuration happens elsewhere.
  """

  @type entry :: %{
          key: atom(),
          display_name: binary(),
          description: binary(),
          available?: boolean()
        }

  @entries [
    %{
      key: :telemetry_decom,
      display_name: "Telemetry Decom",
      description: "Claim packet APIDs and decode selected packets into named telemetry points.",
      available?: true
    },
    %{
      key: :derived_telemetry,
      display_name: "Derived Telemetry",
      description: "Compute telemetry values from raw points (roadmap).",
      available?: false
    }
  ]

  @spec all() :: [entry()]
  def all, do: @entries

  @spec available() :: [entry()]
  def available, do: Enum.filter(@entries, & &1.available?)

  @spec known_keys() :: [atom()]
  def known_keys, do: Enum.map(@entries, & &1.key)
end
