defmodule Cadence.Platform.ConfigurationSettings do
  @moduledoc """
  Mission settings for change sets, in scoped settings section `cadence.configuration`.

  `profile_framing_generations` (default **on** since DECISIONS #45; introduced off by #33): when
  on, applying a change set that changes a profile's framing for its spacecraft also produces a
  runtime activation in which the profile is the framing authority. qa's #33/#36 gates verified
  the compatibility HOLD and a framing change end to end. A mission can still turn it off.
  """

  alias Cadence.Platform.ScopedSettings

  @section "cadence.configuration"
  @default %{"value" => %{"profile_framing_generations" => true}, "allow_override" => true}

  def section_id, do: @section

  @spec profile_framing_generations?(String.t(), String.t()) :: boolean()
  def profile_framing_generations?(organization_id, mission_id) do
    case ScopedSettings.load(organization_id, mission_id, @section, @default).effective do
      %{"profile_framing_generations" => true} -> true
      _ -> false
    end
  end

  @doc "Turns the flag on or off for one mission. `actor` is `%{id, name}`."
  @spec put_profile_framing_generations(String.t(), String.t(), boolean(), map()) ::
          {:ok, term()} | {:error, term()}
  def put_profile_framing_generations(organization_id, mission_id, enabled?, actor)
      when is_boolean(enabled?) do
    current = ScopedSettings.load(organization_id, mission_id, @section, @default)

    ScopedSettings.save(
      organization_id,
      mission_id,
      @section,
      @default,
      current.token,
      %{"value" => %{"profile_framing_generations" => enabled?}},
      actor
    )
  end
end
