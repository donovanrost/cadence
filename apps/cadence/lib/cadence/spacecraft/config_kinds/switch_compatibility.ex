defmodule Cadence.Spacecraft.ConfigKinds.SwitchCompatibility do
  @moduledoc """
  Derived check (L22): HOLDs when a change set turns a spacecraft's commanding or telemetry
  switch. Sentences are ux's (U40):

  - `commanding_command_in_flight` (blocking): a command is being sent to a spacecraft whose
    commanding the set turns off. Abort it or wait for it to finish.
  - `commanding_disabled_cancels_commands` (acknowledge): commands waiting to be sent to it are
    canceled when the set applies (`commanding_disabled`).
  - `telemetry_disabled` (acknowledge): after the apply its telemetry isn't decoded.
  - `telemetry_packet_inputs_required` (blocking): telemetry turned on for a spacecraft whose
    configuration names no packets to decode.
  - `telemetry_app_not_installed` (blocking): telemetry turned on for a spacecraft without the
    telemetry app installed. Install it first: a change set doesn't install applications
    (director 11-15).

  Never staged. The configured generation builder reads what would change.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.ConfigurationSettings

  @impl true
  def kind, do: "switch_compatibility"

  @impl true
  def id_prefix, do: "switch"

  @impl true
  def load(_organization_id, _mission_id, _ids), do: %{}

  @impl true
  def normalize(_action, _id, _document), do: {:error, [F.error("", "This check isn't staged")]}

  @impl true
  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  @impl true
  def write(_organization_id, _mission_id, _action, _id, _previous, _proposed, _options),
    do: {:error, :not_staged}

  @impl true
  def summary(_action, _previous, _proposed), do: "Commanding and telemetry switches"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  @impl true
  def holds(organization_id, mission_id, entries) do
    touched =
      entries
      |> Enum.filter(&(&1.kind == "spacecraft" and &1.op == :update))
      |> Enum.map(& &1.entity_id)
      |> Enum.uniq()

    with [_ | _] <- touched,
         true <- ConfigurationSettings.profile_framing_generations?(organization_id, mission_id),
         builder when builder != nil <- Application.get_env(:cadence, :configuration_generation) do
      impact = builder.switch_impact(organization_id, mission_id, touched)

      Enum.flat_map(impact.commanding_off, &commanding_items/1) ++
        Enum.map(impact.telemetry_off, &telemetry_off_item/1) ++
        Enum.map(impact.missing_inputs, &missing_inputs_item/1) ++
        Enum.map(impact.not_installed, &not_installed_item/1)
    else
      _nothing -> []
    end
  end

  defp commanding_items(%{id: id, name: name, waiting: waiting, in_flight: in_flight}) do
    sending =
      for request <- in_flight do
        item(:commanding_command_in_flight, id, true, %{
          requests: [request],
          sentence:
            "Commanding can't be turned off for #{name} while “#{request.command_name}” is " <>
              "being sent to it. Abort that request or wait for it to finish."
        })
      end

    canceled =
      if waiting == [],
        do: [],
        else: [
          item(:commanding_disabled_cancels_commands, id, false, %{
            requests: waiting,
            sentence:
              "Turning commanding off cancels #{commands(length(waiting))} to be sent to " <>
                "#{name} when this is applied."
          })
        ]

    sending ++ canceled
  end

  defp telemetry_off_item(%{id: id, name: name}),
    do:
      item(:telemetry_disabled, id, false, %{
        sentence:
          "After this is applied, telemetry from #{name} isn't decoded: no live values, " <>
            "alarms or new history until it's turned on again."
      })

  defp missing_inputs_item(%{id: id, name: name}),
    do:
      item(:telemetry_packet_inputs_required, id, true, %{
        sentence:
          "Telemetry can't be turned on for #{name}: its configuration doesn't name the " <>
            "packets to decode. Set its handled APIDs first."
      })

  defp not_installed_item(%{id: id, name: name}),
    do:
      item(:telemetry_app_not_installed, id, true, %{
        sentence:
          "Telemetry can't be turned on for #{name}: the telemetry app isn't installed on it. " <>
            "Install it first."
      })

  defp commands(1), do: "1 command waiting"
  defp commands(n), do: "#{n} commands waiting"

  defp item(reason, spacecraft_id, blocking, extra) do
    Map.merge(
      %{
        op_id: nil,
        change_id: nil,
        kind: "spacecraft",
        entity_id: spacecraft_id,
        reason: reason,
        spacecraft_ids: [spacecraft_id],
        blocking: blocking
      },
      extra
    )
  end
end
