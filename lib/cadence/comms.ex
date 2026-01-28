defmodule Cadence.Comms do
  @moduledoc """
  Control-plane orchestration for spacecraft communications configuration.

  Seeds Links/Channels/Targets to ensure a spacecraft has a default comms setup
  derived from its SCID.
  """

  import Ecto.Query

  alias Cadence.Application.Missions.MissionOperations

  alias Cadence.Links.{
    Binding,
    Channel,
    ChannelActiveSelection,
    ChannelTarget,
    Link,
    ProtocolConfig
  }

  alias Cadence.Repo

  @type organization_id :: Ecto.UUID.t()
  @type mission_id :: Ecto.UUID.t()
  @type target_id :: Ecto.UUID.t()

  @spec seed_for_target!(
          organization_id(),
          mission_id(),
          target_id(),
          non_neg_integer(),
          keyword()
        ) ::
          %{link: Link.t(), channel: Channel.t(), protocol_config: ProtocolConfig.t()}
  def seed_for_target!(organization_id, mission_id, target_id, scid, opts \\ [])
      when is_integer(scid) do
    case seed_for_target(organization_id, mission_id, target_id, scid, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "comms seed failed: #{inspect(reason)}"
    end
  end

  @spec seed_for_target(
          organization_id(),
          mission_id(),
          target_id(),
          non_neg_integer(),
          keyword()
        ) ::
          {:ok, %{link: Link.t(), channel: Channel.t(), protocol_config: ProtocolConfig.t()}}
          | {:error, term()}
  def seed_for_target(organization_id, mission_id, target_id, scid, opts \\ [])
      when is_integer(scid) do
    Repo.transaction(fn ->
      {link, link_created?} =
        get_or_create_link(organization_id, mission_id, scid, Keyword.get(opts, :link_name))

      {protocol_config, protocol_created?} =
        get_or_create_protocol_config(
          organization_id,
          mission_id,
          link.id,
          Keyword.get(opts, :protocol_config, %{})
        )

      {channel, channel_created?} =
        get_or_create_channel(
          organization_id,
          mission_id,
          link,
          Keyword.get(opts, :channel_direction, :both)
        )

      {uplink_target_created?, downlink_target_created?} =
        ensure_channel_targets(organization_id, mission_id, target_id, scid, channel.vcid)

      selection_created? = ensure_uplink_selection(organization_id, mission_id, channel.id)

      if link_created? or protocol_created? or channel_created? or uplink_target_created? or
           downlink_target_created? or selection_created? do
        _ = MissionOperations.bump_config_generation!(mission_id)
      end

      %{link: link, channel: channel, protocol_config: protocol_config}
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_or_create_link(organization_id, mission_id, scid, name) do
    case Repo.get_by(Link,
           organization_id: organization_id,
           mission_id: mission_id,
           scid: scid
         ) do
      %Link{} = link ->
        {link, false}

      nil ->
        attrs =
          %{scid: scid}
          |> maybe_put(:name, name)

        %Link{}
        |> Link.changeset(attrs, organization_id, mission_id)
        |> Repo.insert()
        |> case do
          {:ok, link} -> {link, true}
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp get_or_create_protocol_config(organization_id, mission_id, link_id, config) do
    case Repo.get_by(ProtocolConfig,
           organization_id: organization_id,
           mission_id: mission_id,
           link_id: link_id
         ) do
      %ProtocolConfig{} = protocol_config ->
        {protocol_config, false}

      nil ->
        %ProtocolConfig{}
        |> ProtocolConfig.changeset(
          %{link_id: link_id, config: config},
          organization_id,
          mission_id
        )
        |> Repo.insert()
        |> case do
          {:ok, protocol_config} -> {protocol_config, true}
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp get_or_create_channel(organization_id, mission_id, %Link{} = link, direction) do
    channel =
      Channel
      |> where(
        [c],
        c.organization_id == ^organization_id and c.mission_id == ^mission_id and
          c.link_id == ^link.id and c.vcid == 0 and is_nil(c.map_id)
      )
      |> Repo.one()

    case channel do
      %Channel{} = channel ->
        {channel, false}

      nil ->
        attrs = %{link_id: link.id, scid: link.scid, vcid: 0, map_id: nil, direction: direction}

        %Channel{}
        |> Channel.changeset(attrs, organization_id, mission_id)
        |> Repo.insert()
        |> case do
          {:ok, channel} -> {channel, true}
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp ensure_channel_targets(organization_id, mission_id, target_id, scid, vcid) do
    uplink_created? =
      ensure_channel_target(organization_id, mission_id, target_id, scid, vcid, "primary_uplink")

    downlink_created? =
      ensure_channel_target(
        organization_id,
        mission_id,
        target_id,
        scid,
        vcid,
        "primary_downlink"
      )

    {uplink_created?, downlink_created?}
  end

  defp ensure_channel_target(organization_id, mission_id, target_id, scid, vcid, purpose) do
    case fetch_channel_target(organization_id, mission_id, target_id, scid, vcid, purpose) do
      %ChannelTarget{} -> false
      nil -> insert_channel_target(organization_id, mission_id, target_id, scid, vcid, purpose)
    end
  end

  defp fetch_channel_target(organization_id, mission_id, target_id, scid, vcid, purpose) do
    ChannelTarget
    |> where(
      [ct],
      ct.organization_id == ^organization_id and ct.mission_id == ^mission_id and
        ct.target_id == ^target_id and ct.scid == ^scid and ct.vcid == ^vcid and
        is_nil(ct.map_id) and ct.purpose == ^purpose
    )
    |> Repo.one()
  end

  defp insert_channel_target(organization_id, mission_id, target_id, scid, vcid, purpose) do
    %ChannelTarget{}
    |> ChannelTarget.changeset(
      %{target_id: target_id, scid: scid, vcid: vcid, map_id: nil, purpose: purpose},
      organization_id,
      mission_id
    )
    |> Repo.insert()
    |> case do
      {:ok, _channel_target} -> true
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp ensure_uplink_selection(organization_id, mission_id, channel_id) do
    case Repo.get_by(ChannelActiveSelection,
           organization_id: organization_id,
           mission_id: mission_id,
           channel_id: channel_id,
           direction: :uplink
         ) do
      %ChannelActiveSelection{} ->
        false

      nil ->
        binding_id = highest_priority_binding_id(channel_id, :uplink)

        %ChannelActiveSelection{}
        |> ChannelActiveSelection.changeset(
          %{channel_id: channel_id, direction: :uplink, binding_id: binding_id},
          organization_id,
          mission_id
        )
        |> Repo.insert()
        |> case do
          {:ok, _selection} -> true
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp highest_priority_binding_id(channel_id, direction) do
    bindings =
      Binding
      |> where([b], b.channel_id == ^channel_id and b.direction in ^[direction, :both])
      |> Repo.all()

    bindings
    |> Enum.sort_by(fn binding -> {role_rank(binding.role), binding.priority} end)
    |> case do
      [binding | _] -> binding.id
      [] -> nil
    end
  end

  defp role_rank(:primary), do: 0
  defp role_rank(:any), do: 1
  defp role_rank(:backup), do: 2
  defp role_rank(:replay), do: 3
  defp role_rank(_), do: 4

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
