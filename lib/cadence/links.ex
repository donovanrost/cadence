defmodule Cadence.Links do
  @moduledoc """
  Context for managing links, channels, bindings, and protocol config.
  """

  import Ecto.Query

  alias Cadence.Links.{
    Binding,
    Channel,
    ChannelActiveSelection,
    ChannelProtocolConfig,
    ChannelTarget,
    Link,
    ProtocolConfig
  }

  alias Cadence.Application.Missions.MissionOperations
  alias Cadence.Repo

  @type organization_id :: Ecto.UUID.t()
  @type mission_id :: Ecto.UUID.t()

  @spec create_link(organization_id(), mission_id(), map()) ::
          {:ok, Link.t()} | {:error, Ecto.Changeset.t()}
  def create_link(organization_id, mission_id, attrs) do
    %Link{}
    |> Link.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update_link(organization_id(), mission_id(), Link.t(), map()) ::
          {:ok, Link.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_link(organization_id, mission_id, %Link{} = link, attrs) do
    if link.organization_id == organization_id and link.mission_id == mission_id do
      link
      |> Link.update_changeset(attrs)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec create_channel(organization_id(), mission_id(), map()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def create_channel(organization_id, mission_id, attrs) do
    attrs = merge_scid_from_link(attrs, organization_id, mission_id)

    %Channel{}
    |> Channel.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update_channel(organization_id(), mission_id(), Channel.t(), map()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_channel(organization_id, mission_id, %Channel{} = channel, attrs) do
    if channel.organization_id == organization_id and channel.mission_id == mission_id do
      channel
      |> Channel.update_changeset(attrs)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec create_binding(organization_id(), mission_id(), map()) ::
          {:ok, Binding.t()} | {:error, Ecto.Changeset.t()}
  def create_binding(organization_id, mission_id, attrs) do
    %Binding{}
    |> Binding.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update_binding(organization_id(), mission_id(), Binding.t(), map()) ::
          {:ok, Binding.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_binding(organization_id, mission_id, %Binding{} = binding, attrs) do
    if binding.organization_id == organization_id and binding.mission_id == mission_id do
      binding
      |> Binding.update_changeset(attrs)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec create_protocol_config(organization_id(), mission_id(), map()) ::
          {:ok, ProtocolConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_protocol_config(organization_id, mission_id, attrs) do
    %ProtocolConfig{}
    |> ProtocolConfig.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update_protocol_config(organization_id(), mission_id(), ProtocolConfig.t(), map()) ::
          {:ok, ProtocolConfig.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_protocol_config(organization_id, mission_id, %ProtocolConfig{} = config, attrs) do
    if config.organization_id == organization_id and config.mission_id == mission_id do
      config
      |> ProtocolConfig.update_changeset(attrs)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec create_channel_protocol_config(organization_id(), mission_id(), map()) ::
          {:ok, ChannelProtocolConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_channel_protocol_config(organization_id, mission_id, attrs) do
    %ChannelProtocolConfig{}
    |> ChannelProtocolConfig.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update_channel_protocol_config(
          organization_id(),
          mission_id(),
          ChannelProtocolConfig.t(),
          map()
        ) ::
          {:ok, ChannelProtocolConfig.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized}
  def update_channel_protocol_config(
        organization_id,
        mission_id,
        %ChannelProtocolConfig{} = config,
        attrs
      ) do
    if config.organization_id == organization_id and config.mission_id == mission_id do
      config
      |> ChannelProtocolConfig.update_changeset(attrs)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec create_active_selection(organization_id(), mission_id(), map()) ::
          {:ok, ChannelActiveSelection.t()} | {:error, Ecto.Changeset.t()}
  def create_active_selection(organization_id, mission_id, attrs) do
    %ChannelActiveSelection{}
    |> ChannelActiveSelection.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update_active_selection(
          organization_id(),
          mission_id(),
          ChannelActiveSelection.t(),
          map()
        ) ::
          {:ok, ChannelActiveSelection.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized}
  def update_active_selection(
        organization_id,
        mission_id,
        %ChannelActiveSelection{} = selection,
        attrs
      ) do
    if selection.organization_id == organization_id and selection.mission_id == mission_id do
      selection
      |> ChannelActiveSelection.changeset(attrs, organization_id, mission_id)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec list_links_with_protocol_config(organization_id(), mission_id()) :: [Link.t()]
  def list_links_with_protocol_config(organization_id, mission_id) do
    Link
    |> where([l], l.organization_id == ^organization_id and l.mission_id == ^mission_id)
    |> preload([:protocol_config, channels: [:protocol_config]])
    |> Repo.all()
  end

  @spec list_bindings(organization_id(), mission_id()) :: [Binding.t()]
  def list_bindings(organization_id, mission_id) do
    Binding
    |> where([b], b.organization_id == ^organization_id and b.mission_id == ^mission_id)
    |> preload([:channel])
    |> Repo.all()
  end

  @spec list_bindings_for_interface(organization_id(), mission_id(), Ecto.UUID.t(), keyword()) ::
          [Binding.t()]
  def list_bindings_for_interface(organization_id, mission_id, interface_id, opts \\ []) do
    direction = Keyword.get(opts, :direction)
    desired_states = Keyword.get(opts, :desired_states)

    query =
      Binding
      |> join(:inner, [b], c in assoc(b, :channel))
      |> where(
        [b, c],
        b.organization_id == ^organization_id and b.mission_id == ^mission_id and
          b.interface_id == ^interface_id and c.enabled == true
      )
      |> preload([_b, c], channel: c)

    query =
      if direction do
        where(query, [b, _c], b.direction in ^[direction, :both])
      else
        query
      end

    query =
      if is_list(desired_states) and desired_states != [] do
        where(query, [b, _c], b.desired_state in ^desired_states)
      else
        query
      end

    Repo.all(query)
  end

  @spec list_active_selections(organization_id(), mission_id()) :: [ChannelActiveSelection.t()]
  def list_active_selections(organization_id, mission_id) do
    ChannelActiveSelection
    |> where([s], s.organization_id == ^organization_id and s.mission_id == ^mission_id)
    |> preload([:binding, :channel])
    |> Repo.all()
  end

  @spec create_channel_target(organization_id(), mission_id(), map()) ::
          {:ok, ChannelTarget.t()} | {:error, Ecto.Changeset.t()}
  def create_channel_target(organization_id, mission_id, attrs) do
    %ChannelTarget{}
    |> ChannelTarget.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec list_channel_targets(organization_id(), mission_id(), String.t()) :: [ChannelTarget.t()]
  def list_channel_targets(organization_id, mission_id, target_id) do
    ChannelTarget
    |> where(
      [ct],
      ct.organization_id == ^organization_id and ct.mission_id == ^mission_id and
        ct.target_id == ^target_id
    )
    |> Repo.all()
  end

  @spec list_channel_targets_for_mission(organization_id(), mission_id()) :: [ChannelTarget.t()]
  def list_channel_targets_for_mission(organization_id, mission_id) do
    ChannelTarget
    |> where([ct], ct.organization_id == ^organization_id and ct.mission_id == ^mission_id)
    |> Repo.all()
  end

  # Link CRUD functions

  @spec list_links(organization_id(), mission_id()) :: [Link.t()]
  def list_links(organization_id, mission_id) do
    Link
    |> where([l], l.organization_id == ^organization_id and l.mission_id == ^mission_id)
    |> order_by([l], asc: l.scid)
    |> preload([:protocol_config, channels: [:protocol_config]])
    |> Repo.all()
  end

  @spec get_link(organization_id(), mission_id(), Ecto.UUID.t()) ::
          {:ok, Link.t()} | {:error, :not_found}
  def get_link(organization_id, mission_id, link_id) do
    link =
      Link
      |> where([l], l.organization_id == ^organization_id and l.mission_id == ^mission_id)
      |> preload([:protocol_config, channels: [:protocol_config]])
      |> Repo.get(link_id)

    if link, do: {:ok, link}, else: {:error, :not_found}
  end

  @spec get_link!(organization_id(), mission_id(), Ecto.UUID.t()) :: Link.t()
  def get_link!(organization_id, mission_id, link_id) do
    Link
    |> where([l], l.organization_id == ^organization_id and l.mission_id == ^mission_id)
    |> preload([:channels, :protocol_config])
    |> Repo.get!(link_id)
  end

  @spec delete_link(organization_id(), mission_id(), Link.t()) ::
          {:ok, Link.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_link(organization_id, mission_id, %Link{} = link) do
    if link.organization_id == organization_id and link.mission_id == mission_id do
      Repo.delete(link)
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec change_link(Link.t()) :: Ecto.Changeset.t()
  def change_link(%Link{} = link) do
    Link.update_changeset(link, %{})
  end

  @spec change_link(Link.t(), map()) :: Ecto.Changeset.t()
  def change_link(%Link{} = link, attrs) do
    Link.update_changeset(link, attrs)
  end

  # Channel CRUD functions

  @spec list_channels_for_link(organization_id(), mission_id(), Ecto.UUID.t()) :: [Channel.t()]
  def list_channels_for_link(organization_id, mission_id, link_id) do
    Channel
    |> where(
      [c],
      c.organization_id == ^organization_id and c.mission_id == ^mission_id and
        c.link_id == ^link_id
    )
    |> order_by([c], asc: c.vcid)
    |> preload([:bindings])
    |> Repo.all()
  end

  @spec get_channel(organization_id(), mission_id(), Ecto.UUID.t()) ::
          {:ok, Channel.t()} | {:error, :not_found}
  def get_channel(organization_id, mission_id, channel_id) do
    channel =
      Channel
      |> where([c], c.organization_id == ^organization_id and c.mission_id == ^mission_id)
      |> preload([:bindings, :link])
      |> Repo.get(channel_id)

    if channel, do: {:ok, channel}, else: {:error, :not_found}
  end

  @spec get_channel!(organization_id(), mission_id(), Ecto.UUID.t()) :: Channel.t()
  def get_channel!(organization_id, mission_id, channel_id) do
    Channel
    |> where([c], c.organization_id == ^organization_id and c.mission_id == ^mission_id)
    |> preload([:bindings, :link])
    |> Repo.get!(channel_id)
  end

  @spec delete_channel(organization_id(), mission_id(), Channel.t()) ::
          {:ok, Channel.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_channel(organization_id, mission_id, %Channel{} = channel) do
    if channel.organization_id == organization_id and channel.mission_id == mission_id do
      Repo.delete(channel)
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec change_channel(Channel.t()) :: Ecto.Changeset.t()
  def change_channel(%Channel{} = channel) do
    Channel.update_changeset(channel, %{})
  end

  @spec change_channel(Channel.t(), map()) :: Ecto.Changeset.t()
  def change_channel(%Channel{} = channel, attrs) do
    Channel.update_changeset(channel, attrs)
  end

  # Binding CRUD functions

  @spec list_bindings_for_channel(organization_id(), mission_id(), Ecto.UUID.t()) :: [Binding.t()]
  def list_bindings_for_channel(organization_id, mission_id, channel_id) do
    Binding
    |> where(
      [b],
      b.organization_id == ^organization_id and b.mission_id == ^mission_id and
        b.channel_id == ^channel_id
    )
    |> order_by([b], asc: b.priority)
    |> preload([:interface])
    |> Repo.all()
  end

  @spec get_binding(organization_id(), mission_id(), Ecto.UUID.t()) ::
          {:ok, Binding.t()} | {:error, :not_found}
  def get_binding(organization_id, mission_id, binding_id) do
    binding =
      Binding
      |> where([b], b.organization_id == ^organization_id and b.mission_id == ^mission_id)
      |> preload([:interface, :channel])
      |> Repo.get(binding_id)

    if binding, do: {:ok, binding}, else: {:error, :not_found}
  end

  @spec get_binding!(organization_id(), mission_id(), Ecto.UUID.t()) :: Binding.t()
  def get_binding!(organization_id, mission_id, binding_id) do
    Binding
    |> where([b], b.organization_id == ^organization_id and b.mission_id == ^mission_id)
    |> preload([:interface, :channel])
    |> Repo.get!(binding_id)
  end

  @spec delete_binding(organization_id(), mission_id(), Binding.t()) ::
          {:ok, Binding.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_binding(organization_id, mission_id, %Binding{} = binding) do
    if binding.organization_id == organization_id and binding.mission_id == mission_id do
      Repo.delete(binding)
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @spec change_binding(Binding.t()) :: Ecto.Changeset.t()
  def change_binding(%Binding{} = binding) do
    Binding.update_changeset(binding, %{})
  end

  @spec change_binding(Binding.t(), map()) :: Ecto.Changeset.t()
  def change_binding(%Binding{} = binding, attrs) do
    Binding.update_changeset(binding, attrs)
  end

  # Protocol Config functions

  @spec get_protocol_config_for_link(organization_id(), mission_id(), Ecto.UUID.t()) ::
          {:ok, ProtocolConfig.t()} | {:error, :not_found}
  def get_protocol_config_for_link(organization_id, mission_id, link_id) do
    config =
      ProtocolConfig
      |> where(
        [p],
        p.organization_id == ^organization_id and p.mission_id == ^mission_id and
          p.link_id == ^link_id
      )
      |> Repo.one()

    if config, do: {:ok, config}, else: {:error, :not_found}
  end

  @spec change_protocol_config(ProtocolConfig.t()) :: Ecto.Changeset.t()
  def change_protocol_config(%ProtocolConfig{} = config) do
    ProtocolConfig.update_changeset(config, %{})
  end

  @spec change_protocol_config(ProtocolConfig.t(), map()) :: Ecto.Changeset.t()
  def change_protocol_config(%ProtocolConfig{} = config, attrs) do
    ProtocolConfig.update_changeset(config, attrs)
  end

  defp maybe_bump_config_generation({:ok, _record} = result, mission_id) do
    _ = MissionOperations.bump_config_generation!(mission_id)
    result
  end

  defp maybe_bump_config_generation(result, _mission_id), do: result

  defp merge_scid_from_link(attrs, organization_id, mission_id) do
    attrs = normalize_scid_attr(attrs)
    scid = Map.get(attrs, :scid) || Map.get(attrs, "scid")

    if is_integer(scid) do
      attrs
    else
      link_id = Map.get(attrs, :link_id) || Map.get(attrs, "link_id")

      case fetch_link_scid(link_id, organization_id, mission_id) do
        nil -> attrs
        link_scid -> Map.put(attrs, :scid, link_scid)
      end
    end
  end

  defp normalize_scid_attr(attrs) when is_map(attrs) do
    case Map.get(attrs, :scid) || Map.get(attrs, "scid") do
      nil ->
        attrs

      scid when is_integer(scid) ->
        attrs

      scid when is_binary(scid) ->
        case Integer.parse(scid) do
          {int, ""} -> Map.put(attrs, :scid, int)
          _ -> attrs
        end

      _ ->
        attrs
    end
  end

  defp fetch_link_scid(nil, _organization_id, _mission_id), do: nil

  defp fetch_link_scid(link_id, organization_id, mission_id) do
    Link
    |> where([l], l.organization_id == ^organization_id and l.mission_id == ^mission_id)
    |> Repo.get(link_id)
    |> case do
      %Link{scid: scid} when is_integer(scid) -> scid
      _ -> nil
    end
  end

  # ===========================================================================
  # Spacecraft-centric query functions
  # ===========================================================================

  @doc """
  Gets a link by SCID for a given mission.

  Returns `{:ok, link}` if found (with protocol_config and channels preloaded),
  `{:error, :not_found}` otherwise.
  """
  @spec get_link_by_scid(organization_id(), mission_id(), integer()) ::
          {:ok, Link.t()} | {:error, :not_found}
  def get_link_by_scid(organization_id, mission_id, scid) do
    Link
    |> where(
      [l],
      l.organization_id == ^organization_id and l.mission_id == ^mission_id and l.scid == ^scid
    )
    |> preload([:protocol_config, channels: [:protocol_config, :bindings]])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  @doc """
  Gets or creates a channel protocol config for a channel.

  If a ChannelProtocolConfig exists for the channel, returns it.
  Otherwise, creates a new one with empty overrides.
  """
  @spec get_or_create_channel_protocol_config(
          organization_id(),
          mission_id(),
          Ecto.UUID.t()
        ) ::
          {:ok, ChannelProtocolConfig.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_channel_protocol_config(organization_id, mission_id, channel_id) do
    case get_channel_protocol_config(organization_id, mission_id, channel_id) do
      {:ok, config} ->
        {:ok, config}

      {:error, :not_found} ->
        create_channel_protocol_config(organization_id, mission_id, %{channel_id: channel_id})
    end
  end

  @doc """
  Gets a channel protocol config.
  """
  @spec get_channel_protocol_config(organization_id(), mission_id(), Ecto.UUID.t()) ::
          {:ok, ChannelProtocolConfig.t()} | {:error, :not_found}
  def get_channel_protocol_config(organization_id, mission_id, channel_id) do
    config =
      ChannelProtocolConfig
      |> where(
        [c],
        c.organization_id == ^organization_id and c.mission_id == ^mission_id and
          c.channel_id == ^channel_id
      )
      |> Repo.one()

    if config, do: {:ok, config}, else: {:error, :not_found}
  end

  @doc """
  Gets active selections for a channel.
  """
  @spec get_active_selections_for_channel(organization_id(), mission_id(), Ecto.UUID.t()) ::
          [ChannelActiveSelection.t()]
  def get_active_selections_for_channel(organization_id, mission_id, channel_id) do
    ChannelActiveSelection
    |> where(
      [s],
      s.organization_id == ^organization_id and s.mission_id == ^mission_id and
        s.channel_id == ^channel_id
    )
    |> preload([:binding])
    |> Repo.all()
  end

  @doc """
  Updates or creates an active selection for a channel and direction.
  """
  @spec upsert_active_selection(
          organization_id(),
          mission_id(),
          Ecto.UUID.t(),
          atom(),
          Ecto.UUID.t() | nil
        ) ::
          {:ok, ChannelActiveSelection.t()} | {:error, term()}
  def upsert_active_selection(organization_id, mission_id, channel_id, direction, binding_id) do
    # Find existing selection for this channel/direction
    existing =
      ChannelActiveSelection
      |> where(
        [s],
        s.organization_id == ^organization_id and s.mission_id == ^mission_id and
          s.channel_id == ^channel_id and s.direction == ^direction
      )
      |> Repo.one()

    case existing do
      nil ->
        # Create new
        create_active_selection(organization_id, mission_id, %{
          channel_id: channel_id,
          direction: direction,
          binding_id: binding_id
        })

      selection ->
        # Update existing
        update_active_selection(organization_id, mission_id, selection, %{binding_id: binding_id})
    end
  end

  @doc """
  Updates or creates a primary channel mapping for a target.

  The purpose should be "primary_uplink" or "primary_downlink".
  """
  @spec upsert_primary_channel(
          organization_id(),
          mission_id(),
          String.t(),
          String.t(),
          Ecto.UUID.t()
        ) ::
          {:ok, ChannelTarget.t()} | {:error, term()}
  def upsert_primary_channel(organization_id, mission_id, target_id, purpose, channel_id) do
    # Get channel to find SCID/VCID
    case get_channel(organization_id, mission_id, channel_id) do
      {:ok, channel} ->
        # Find existing mapping for this target/purpose
        existing =
          ChannelTarget
          |> where(
            [ct],
            ct.organization_id == ^organization_id and ct.mission_id == ^mission_id and
              ct.target_id == ^target_id and ct.purpose == ^purpose
          )
          |> Repo.one()

        attrs = %{
          target_id: target_id,
          scid: channel.scid,
          vcid: channel.vcid,
          map_id: channel.map_id,
          purpose: purpose
        }

        case existing do
          nil ->
            create_channel_target(organization_id, mission_id, attrs)

          channel_target ->
            update_channel_target(organization_id, mission_id, channel_target, attrs)
        end

      {:error, :not_found} ->
        {:error, :channel_not_found}
    end
  end

  @doc """
  Removes a primary channel mapping for a target.
  """
  @spec delete_primary_channel(organization_id(), mission_id(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def delete_primary_channel(organization_id, mission_id, target_id, purpose) do
    ChannelTarget
    |> where(
      [ct],
      ct.organization_id == ^organization_id and ct.mission_id == ^mission_id and
        ct.target_id == ^target_id and ct.purpose == ^purpose
    )
    |> Repo.delete_all()

    _ = MissionOperations.bump_config_generation!(mission_id)
    :ok
  end

  @doc """
  Updates a channel target mapping.
  """
  @spec update_channel_target(organization_id(), mission_id(), ChannelTarget.t(), map()) ::
          {:ok, ChannelTarget.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_channel_target(organization_id, mission_id, %ChannelTarget{} = channel_target, attrs) do
    if channel_target.organization_id == organization_id and
         channel_target.mission_id == mission_id do
      channel_target
      |> ChannelTarget.changeset(attrs, organization_id, mission_id)
      |> Repo.update()
      |> maybe_bump_config_generation(mission_id)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Gets a primary channel mapping for a target.
  """
  @spec get_primary_channel(organization_id(), mission_id(), String.t(), String.t()) ::
          {:ok, ChannelTarget.t()} | {:error, :not_found}
  def get_primary_channel(organization_id, mission_id, target_id, purpose) do
    channel_target =
      ChannelTarget
      |> where(
        [ct],
        ct.organization_id == ^organization_id and ct.mission_id == ^mission_id and
          ct.target_id == ^target_id and ct.purpose == ^purpose
      )
      |> Repo.one()

    if channel_target, do: {:ok, channel_target}, else: {:error, :not_found}
  end
end
