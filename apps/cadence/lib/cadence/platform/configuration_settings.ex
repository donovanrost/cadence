defmodule Cadence.Configuration.Settings do
  @moduledoc """
  Mission settings for change sets, in scoped settings section `cadence.configuration`.

  `profile_framing_generations` (default **off**, DECISIONS #33): when on, applying a change set
  that changes a profile's framing or catalog for its spacecraft also produces a runtime
  activation in which the profile is the framing authority. It stays off until the review page
  shows the framing compatibility HOLD and a framing change is verified end to end.
  """

  alias Cadence.Platform.ScopedSettings

  @section "cadence.configuration"
  @default %{"value" => %{"profile_framing_generations" => false}, "allow_override" => true}

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
