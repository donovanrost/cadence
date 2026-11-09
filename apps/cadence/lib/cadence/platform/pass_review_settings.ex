defmodule Cadence.Platform.PassReviewSettings do
  @moduledoc """
  Pass review settings (S9, DECISIONS #48), scoped section `cadence.pass_review`:

  - `pass_realized_threshold` (default 0.95): a pass counts as realized when it flew at least
    this share of its planned window;
  - `realization_target` (default 0.98): the fleet's target share of realized passes (K3's R3
    target line and h1 verdict).

  Set for the organization and overridable per mission. Edited in Settings through
  `Cadence.Management.PassReviewSettingsSection`.
  """

  alias Cadence.Platform.ScopedSettings

  @section "cadence.pass_review"
  @default %{
    "value" => %{"pass_realized_threshold" => 0.95, "realization_target" => 0.98},
    "allow_override" => true
  }

  def section_id, do: @section
  def default, do: @default
  def keys, do: Map.keys(@default["value"])

  def load(organization_id, mission_id),
    do: ScopedSettings.load(organization_id, mission_id, @section, @default)

  @doc "Effective `%{threshold, target}` for a mission."
  @spec effective(String.t(), String.t()) :: %{threshold: number(), target: number()}
  def effective(organization_id, mission_id) do
    value = Map.merge(@default["value"], load(organization_id, mission_id).effective || %{})
    %{threshold: value["pass_realized_threshold"], target: value["realization_target"]}
  end
end
