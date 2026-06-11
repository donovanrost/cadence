defmodule Cadence.Applications.Catalog do
  @moduledoc """
  Registry for platform applications known to Cadence.

  Application keys are durable strings so first-party and future organization
  uploaded applications can share the same persistence shape without creating
  runtime atoms from user-controlled input.
  """

  @type application_key :: binary()

  @type entry :: %{
          key: application_key(),
          display_name: binary(),
          description: binary(),
          available?: boolean()
        }

  @entries [
    %{
      key: "telemetry_decom",
      display_name: "Telemetry Decom",
      description: "Claim packet APIDs and decode selected packets into named telemetry points.",
      available?: true
    },
    %{
      key: "derived_telemetry",
      display_name: "Derived Telemetry",
      description: "Compute telemetry values from raw points (roadmap).",
      available?: false
    }
  ]

  @spec all() :: [entry()]
  def all, do: @entries

  @spec available() :: [entry()]
  def available, do: Enum.filter(@entries, & &1.available?)

  @spec known_keys() :: [application_key()]
  def known_keys, do: Enum.map(@entries, & &1.key)
end
