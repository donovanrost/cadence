defmodule Cadence.Reads.TelemetryApplyRefusals do
  @moduledoc """
  The words for an apply that refused to turn telemetry on (ux U63; api-ops' note): the preview's
  blocking hold normally says it first, but a change set applied anyway answers in words, never a
  generic failure. Up to three spacecraft are named in full ("A, B and C"), else "12 spacecraft".

    * `telemetry_app_not_installed`: "Not applied: the telemetry app isn't installed on
      EARENDIL-312. Install the app in Setup › Apps first."
    * `telemetry_packet_inputs_required`: "Not applied: telemetry can't be turned on for
      EARENDIL-312 until its packet inputs are set up."
  """

  alias Cadence.SpacecraftStore

  @typedoc """
  A refusal as data (api-ops, ca-ux on #556): `why` is the reason clause (no opener, no period),
  `then` an optional next sentence, so callers word it per act without parsing a sentence.
  """
  @type refusal :: %{required(:why) => binary(), optional(:then) => binary()}

  @spec message(atom(), [binary()], binary() | nil, binary() | nil) :: binary()
  def message(tag, ids, organization_id, mission_id),
    do: tag |> refusal(names(ids, organization_id, mission_id)) |> to_sentence()

  @doc "The refusal, as data, for spacecraft `ids` (their names resolved in the mission)."
  @spec refusal(atom(), [binary()], binary() | nil, binary() | nil) :: refusal()
  def refusal(tag, ids, organization_id, mission_id),
    do: refusal(tag, names(ids, organization_id, mission_id))

  @doc "The sentence for already-resolved spacecraft names."
  @spec sentence(atom(), [binary()]) :: binary()
  def sentence(tag, names), do: tag |> refusal(names) |> to_sentence()

  @spec refusal(atom(), [binary()]) :: refusal()
  def refusal(:telemetry_app_not_installed, names),
    do: %{
      why: "the telemetry app isn't installed on #{label(names)}",
      then: "Install the app in Setup › Apps first."
    }

  def refusal(:telemetry_packet_inputs_required, names),
    do: %{
      why:
        "telemetry can't be turned on for #{label(names)} until " <>
          "#{if length(names) == 1, do: "its", else: "their"} packet inputs are set up"
    }

  defp to_sentence(%{why: why} = refusal),
    do: Enum.join(["Not applied: " <> why <> "." | List.wrap(refusal[:then])], " ")

  defp label([one]), do: one
  defp label([a, b]), do: "#{a} and #{b}"
  defp label([a, b, c]), do: "#{a}, #{b} and #{c}"
  defp label(names), do: "#{length(names)} spacecraft"

  # A name the store doesn't know stays its id; without a mission scope, ids are all we have.
  defp names(ids, organization_id, mission_id)
       when is_binary(organization_id) and is_binary(mission_id) and length(ids) <= 3 do
    known =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Map.new(&{&1.spacecraft_id, &1.display_name})

    Enum.map(ids, &(Map.get(known, &1) || &1))
  end

  defp names(ids, _organization_id, _mission_id), do: ids
end
