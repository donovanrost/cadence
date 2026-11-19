defmodule Cadence.Comms.ConfigKinds.FramingCompatibility do
  @moduledoc """
  Derived check (DECISIONS #33): with profile framing generations on, applying a change set
  makes the profile the framing authority for the spacecraft it touches, so decode switches
  from the transport's ingress metadata to the profile's framing. Every difference becomes a
  compatibility HOLD that names both values; the reviewer must acknowledge holds before
  applying. Never staged.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.FramingDrift
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.ConfigurationSettings

  @impl true
  def kind, do: "framing_compatibility"

  @impl true
  def id_prefix, do: "framing"

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
  def summary(_action, _previous, _proposed), do: "Framing compatibility"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  @impl true
  def holds(organization_id, mission_id, entries) do
    touched =
      entries
      |> Enum.filter(&(&1.kind in ["spacecraft", "spacecraft_override"] and &1.op == :update))
      |> Enum.map(& &1.entity_id)
      |> Enum.uniq()
      |> framing_changes(organization_id, mission_id)

    if touched != [] and
         ConfigurationSettings.profile_framing_generations?(organization_id, mission_id) do
      Enum.flat_map(FramingDrift.audit(organization_id, mission_id, touched), &items/1) ++
        Enum.map(
          FramingDrift.unverified(organization_id, mission_id, touched),
          &unverified_item/1
        )
    else
      []
    end
  end

  # Only spacecraft whose runtime framing the apply would change, as the configured generation
  # builder decides (the same one that builds the activation), so a routing-only edit doesn't
  # hold. No builder configured means no framing generation, so nothing to hold.
  defp framing_changes([], _organization_id, _mission_id), do: []

  defp framing_changes(ids, organization_id, mission_id) do
    case Application.get_env(:cadence, :configuration_generation) do
      nil -> []
      builder -> builder.changed_spacecraft(organization_id, mission_id, ids)
    end
  end

  # DECISIONS #40: fail closed when the transport framing can't be determined.
  defp unverified_item(%{profile: profile, cause: cause, spacecraft_count: count}) do
    why =
      case cause do
        :no_inbound_route -> "they have no inbound route"
        :no_ingress_metadata -> "their transports declare no ingress frame size"
      end

    %{
      op_id: nil,
      change_id: nil,
      kind: "spacecraft_profile",
      entity_id: profile.id,
      reason: :framing_unverified,
      cause: cause,
      spacecraft_count: count,
      profile_value: nil,
      transport_value: nil,
      sentence:
        "#{count} spacecraft on #{profile.name} will decode with the profile's framing, but " <>
          "it can't be checked against their transports because #{why}."
    }
  end

  defp items(drift) do
    Enum.map(drift.differences, fn difference ->
      %{
        op_id: nil,
        change_id: nil,
        kind: "spacecraft_profile",
        entity_id: drift.profile.id,
        reason: :framing_mismatch,
        spacecraft_count: drift.spacecraft_count,
        profile_value: %{path: difference.path, value: difference.profile_value},
        transport_value: %{
          transport: drift.transport,
          path:
            "ingress_metadata." <> String.replace_prefix(difference.path, "frame_parameters.", ""),
          value: difference.transport_value
        },
        # ux: a plain sentence with units; the raw comparison stays in `detail`.
        sentence:
          "#{drift.spacecraft_count} spacecraft on #{drift.profile.name} would decode " <>
            "#{framing(difference.path, difference.profile_value)}, but " <>
            "#{drift.transport.name} sends #{framing(difference.path, difference.transport_value)}.",
        detail:
          "#{difference.path} = #{inspect(difference.profile_value)} (profile) vs " <>
            "ingress_metadata.#{String.replace_prefix(difference.path, "frame_parameters.", "")} = " <>
            "#{inspect(difference.transport_value)} (#{drift.transport.name})"
      }
    end)
  end

  defp framing("frame_parameters.frame_size", value), do: "#{bytes(value)} frames"

  defp framing("frame_parameters.secondary_header_length", value),
    do: "a #{bytes(value)} secondary header"

  defp framing("frame_parameters.ocf_length", value), do: "a #{bytes(value)} OCF"
  defp framing("frame_parameters.fecf", true), do: "frames with an FECF"
  defp framing("frame_parameters.fecf", false), do: "frames without an FECF"
  defp framing(path, value), do: "#{path} #{inspect(value)}"

  defp bytes(value) when is_integer(value), do: "#{thousands(value)}-byte"
  defp bytes(value), do: inspect(value)

  defp thousands(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
