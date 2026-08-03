defmodule Cadence.Dashboards.Management do
  @moduledoc """
  Durable management layer for dashboard sharing, snapshots, reusable widget
  versions, and playlists.

  All reads are organization and mission scoped. Library consumers always pin
  an exact version; resolution never substitutes the latest version.
  """

  import Ecto.Query

  alias Cadence.Dashboards.{
    DashboardDeployment,
    DashboardLibraryItem,
    DashboardLibraryVersion,
    DashboardPlaylist,
    DashboardShare,
    DashboardSnapshot,
    Document,
    DocumentStore,
    Placement,
    ValidationResult,
    WidgetDef
  }

  alias Cadence.Repo

  @runtime_context_keys ~w(
    spacecraft_id scope_kind scope_id time_mode time_axis from to replay_run_id realm data_view
    data_source_id source_binding_id limit_mode selected_target selected_id
  )

  @spec record_deployment(binary(), binary(), Document.t(), binary(), binary(), keyword()) ::
          {:ok, DashboardDeployment.t()} | {:error, term()}
  def record_deployment(
        organization_id,
        mission_id,
        %Document{} = document,
        artifact,
        environment,
        opts \\ []
      )
      when is_binary(artifact) and is_binary(environment) do
    with :ok <- validate_document_scope(document, organization_id, mission_id),
         {:ok, _persisted} <-
           DocumentStore.fetch_document(organization_id, mission_id, document.dashboard_id) do
      %DashboardDeployment{}
      |> DashboardDeployment.changeset(%{
        dashboard_deployment_id: Cadence.Ids.new("dashboard_deployment"),
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: document.dashboard_id,
        dashboard_version: Document.version(document),
        environment: environment,
        artifact_digest: :crypto.hash(:sha256, artifact) |> Base.encode16(case: :lower),
        status: Keyword.get(opts, :status, "exported"),
        created_by: Keyword.get(opts, :created_by)
      })
      |> Repo.insert()
    end
  end

  @spec list_deployments(binary(), binary(), binary()) :: [DashboardDeployment.t()]
  def list_deployments(organization_id, mission_id, dashboard_id) do
    DashboardDeployment
    |> where(
      [deployment],
      deployment.organization_id == ^organization_id and deployment.mission_id == ^mission_id and
        deployment.dashboard_id == ^dashboard_id
    )
    |> order_by([deployment], desc: deployment.inserted_at)
    |> Repo.all()
  end

  @spec create_share(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, DashboardShare.t()} | {:error, term()}
  def create_share(organization_id, mission_id, dashboard_id, runtime_context, opts \\ []) do
    with {:ok, _document} <-
           DocumentStore.fetch_document(organization_id, mission_id, dashboard_id) do
      attrs = %{
        dashboard_share_id: Cadence.Ids.new("dashboard_share"),
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: dashboard_id,
        created_by: Keyword.get(opts, :created_by),
        access_policy: "mission_member",
        data_visibility: Keyword.get(opts, :data_visibility, "authorized_runtime_data"),
        runtime_context: normalize_runtime_context(runtime_context),
        expires_at: share_expiration(opts)
      }

      %DashboardShare{}
      |> DashboardShare.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec list_shares(binary(), binary(), binary()) :: [DashboardShare.t()]
  def list_shares(organization_id, mission_id, dashboard_id) do
    DashboardShare
    |> where(
      [share],
      share.organization_id == ^organization_id and share.mission_id == ^mission_id and
        share.dashboard_id == ^dashboard_id
    )
    |> order_by([share], desc: share.inserted_at)
    |> Repo.all()
  end

  @spec fetch_active_share(binary(), binary(), binary()) ::
          {:ok, DashboardShare.t()}
          | {:error, :dashboard_share_not_found | :dashboard_share_inactive}
  def fetch_active_share(organization_id, mission_id, share_id) do
    case Repo.get_by(DashboardShare,
           dashboard_share_id: share_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      %DashboardShare{} = share ->
        if active_share?(share), do: {:ok, share}, else: {:error, :dashboard_share_inactive}

      nil ->
        {:error, :dashboard_share_not_found}
    end
  end

  @spec revoke_share(binary(), binary(), binary()) ::
          {:ok, DashboardShare.t()} | {:error, :dashboard_share_not_found | Ecto.Changeset.t()}
  def revoke_share(organization_id, mission_id, share_id) do
    case Repo.get_by(DashboardShare,
           dashboard_share_id: share_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      %DashboardShare{} = share ->
        share
        |> DashboardShare.changeset(%{revoked_at: DateTime.utc_now()})
        |> Repo.update()

      nil ->
        {:error, :dashboard_share_not_found}
    end
  end

  @spec create_snapshot(binary(), binary(), Document.t(), map(), keyword()) ::
          {:ok, DashboardSnapshot.t()} | {:error, term()}
  def create_snapshot(organization_id, mission_id, %Document{} = document, runtime_context, opts) do
    with :ok <- validate_document_scope(document, organization_id, mission_id),
         {:ok, _persisted} <-
           DocumentStore.fetch_document(organization_id, mission_id, document.dashboard_id) do
      context = normalize_runtime_context(runtime_context)

      attrs = %{
        dashboard_snapshot_id: Cadence.Ids.new("dashboard_snapshot"),
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: document.dashboard_id,
        dashboard_version: Document.version(document),
        created_by: Keyword.get(opts, :created_by),
        runtime_context: context,
        data_semantics: snapshot_data_semantics(context),
        data_visibility: Keyword.get(opts, :data_visibility, "authorized_runtime_data"),
        document: Document.to_map(document)
      }

      %DashboardSnapshot{}
      |> DashboardSnapshot.changeset(attrs)
      |> Repo.insert()
    end
  end

  @spec list_snapshots(binary(), binary(), binary()) :: [DashboardSnapshot.t()]
  def list_snapshots(organization_id, mission_id, dashboard_id) do
    DashboardSnapshot
    |> where(
      [snapshot],
      snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
        snapshot.dashboard_id == ^dashboard_id
    )
    |> order_by([snapshot], desc: snapshot.inserted_at)
    |> Repo.all()
  end

  @spec fetch_snapshot(binary(), binary(), binary()) ::
          {:ok, DashboardSnapshot.t()} | {:error, :dashboard_snapshot_not_found}
  def fetch_snapshot(organization_id, mission_id, snapshot_id) do
    case Repo.get_by(DashboardSnapshot,
           dashboard_snapshot_id: snapshot_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      %DashboardSnapshot{} = snapshot -> {:ok, snapshot}
      nil -> {:error, :dashboard_snapshot_not_found}
    end
  end

  @spec create_library_item(binary(), binary(), map(), keyword()) ::
          {:ok, DashboardLibraryItem.t()} | {:error, term()}
  def create_library_item(organization_id, mission_id, attrs, opts \\ []) do
    case validate_widget_definition(attrs["widget_definition"] || attrs[:widget_definition]) do
      {:ok, widget_definition} ->
        create_library_item_transaction(
          organization_id,
          mission_id,
          attrs,
          widget_definition,
          opts
        )

      {:error, _reason} = error ->
        error
    end
  end

  @spec add_library_version(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, DashboardLibraryItem.t()} | {:error, term()}
  def add_library_version(organization_id, mission_id, item_id, widget_definition, opts \\ []) do
    case validate_widget_definition(widget_definition) do
      {:ok, widget_definition} ->
        add_library_version_transaction(
          organization_id,
          mission_id,
          item_id,
          widget_definition,
          opts
        )

      {:error, _reason} = error ->
        error
    end
  end

  @spec list_library_items(binary(), binary()) :: [DashboardLibraryItem.t()]
  def list_library_items(organization_id, mission_id) do
    DashboardLibraryItem
    |> where(
      [item],
      item.organization_id == ^organization_id and item.mission_id == ^mission_id
    )
    |> order_by([item], asc: item.name)
    |> Repo.all()
  end

  @spec list_library_versions(binary()) :: [DashboardLibraryVersion.t()]
  def list_library_versions(item_id) do
    DashboardLibraryVersion
    |> where([version], version.dashboard_library_item_id == ^item_id)
    |> order_by([version], desc: version.version)
    |> Repo.all()
  end

  @spec fetch_library_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, DashboardLibraryVersion.t()} | {:error, :dashboard_library_version_not_found}
  def fetch_library_version(organization_id, mission_id, item_id, version) do
    query =
      from(library_version in DashboardLibraryVersion,
        join: item in DashboardLibraryItem,
        on: item.dashboard_library_item_id == library_version.dashboard_library_item_id,
        where:
          item.organization_id == ^organization_id and item.mission_id == ^mission_id and
            item.dashboard_library_item_id == ^item_id and library_version.version == ^version,
        select: library_version
      )

    case Repo.one(query) do
      %DashboardLibraryVersion{} = library_version -> {:ok, library_version}
      nil -> {:error, :dashboard_library_version_not_found}
    end
  end

  @spec resolve_document(Document.t()) :: Document.t()
  def resolve_document(%Document{} = document) do
    placements = Enum.map(document.placements, &resolve_placement(document, &1))
    Document.replace_placements(document, placements)
  end

  @spec library_usage(binary(), binary(), DashboardLibraryItem.t()) :: map()
  def library_usage(organization_id, mission_id, %DashboardLibraryItem{} = item) do
    consumers =
      organization_id
      |> DocumentStore.list_documents(mission_id)
      |> Enum.flat_map(&document_library_consumers(&1, item))

    %{
      consumer_count: length(consumers),
      outdated_count: Enum.count(consumers, & &1.update_available?),
      consumers: consumers
    }
  end

  @spec create_playlist(binary(), binary(), map(), keyword()) ::
          {:ok, DashboardPlaylist.t()} | {:error, term()}
  def create_playlist(organization_id, mission_id, attrs, opts \\ []) do
    dashboard_ids = attrs["dashboard_ids"] || attrs[:dashboard_ids] || []

    with :ok <- validate_playlist_dashboards(organization_id, mission_id, dashboard_ids) do
      %DashboardPlaylist{}
      |> DashboardPlaylist.changeset(%{
        dashboard_playlist_id: Cadence.Ids.new("dashboard_playlist"),
        organization_id: organization_id,
        mission_id: mission_id,
        name: attrs["name"] || attrs[:name],
        description: attrs["description"] || attrs[:description],
        dashboard_ids: dashboard_ids,
        dwell_seconds: attrs["dwell_seconds"] || attrs[:dwell_seconds] || 30,
        wallboard_mode: attrs["wallboard_mode"] || attrs[:wallboard_mode] || false,
        created_by: Keyword.get(opts, :created_by),
        updated_by: Keyword.get(opts, :created_by)
      })
      |> Repo.insert()
    end
  end

  @spec list_playlists(binary(), binary()) :: [DashboardPlaylist.t()]
  def list_playlists(organization_id, mission_id) do
    DashboardPlaylist
    |> where(
      [playlist],
      playlist.organization_id == ^organization_id and playlist.mission_id == ^mission_id
    )
    |> order_by([playlist], asc: playlist.name)
    |> Repo.all()
  end

  @spec fetch_playlist(binary(), binary(), binary()) ::
          {:ok, DashboardPlaylist.t()} | {:error, :dashboard_playlist_not_found}
  def fetch_playlist(organization_id, mission_id, playlist_id) do
    case Repo.get_by(DashboardPlaylist,
           dashboard_playlist_id: playlist_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      %DashboardPlaylist{} = playlist -> {:ok, playlist}
      nil -> {:error, :dashboard_playlist_not_found}
    end
  end

  @spec normalize_runtime_context(map()) :: map()
  def normalize_runtime_context(context) when is_map(context) do
    context
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
    |> Map.take(@runtime_context_keys)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  def normalize_runtime_context(_context), do: %{}

  defp active_share?(share) do
    is_nil(share.revoked_at) and
      (is_nil(share.expires_at) or DateTime.compare(share.expires_at, DateTime.utc_now()) == :gt)
  end

  defp create_library_item_transaction(
         organization_id,
         mission_id,
         attrs,
         widget_definition,
         opts
       ) do
    item_id = Cadence.Ids.new("dashboard_library_item")
    actor_id = Keyword.get(opts, :created_by)

    Repo.transaction(fn ->
      item =
        %DashboardLibraryItem{}
        |> DashboardLibraryItem.changeset(%{
          dashboard_library_item_id: item_id,
          organization_id: organization_id,
          mission_id: mission_id,
          name: attrs["name"] || attrs[:name],
          description: attrs["description"] || attrs[:description],
          latest_version: 1,
          created_by: actor_id,
          updated_by: actor_id
        })
        |> insert_or_rollback()

      %DashboardLibraryVersion{}
      |> DashboardLibraryVersion.changeset(%{
        dashboard_library_version_id: Cadence.Ids.new("dashboard_library_version"),
        dashboard_library_item_id: item_id,
        version: 1,
        widget_definition: widget_definition,
        compatibility: compatibility(widget_definition),
        change_summary: attrs["change_summary"] || attrs[:change_summary] || "Initial version",
        created_by: actor_id
      })
      |> insert_or_rollback()

      item
    end)
  end

  defp add_library_version_transaction(
         organization_id,
         mission_id,
         item_id,
         widget_definition,
         opts
       ) do
    Repo.transaction(fn ->
      item = fetch_library_item_for_update(organization_id, mission_id, item_id)
      next_version = item.latest_version + 1

      %DashboardLibraryVersion{}
      |> DashboardLibraryVersion.changeset(%{
        dashboard_library_version_id: Cadence.Ids.new("dashboard_library_version"),
        dashboard_library_item_id: item_id,
        version: next_version,
        widget_definition: widget_definition,
        compatibility: compatibility(widget_definition),
        change_summary: Keyword.get(opts, :change_summary, "Updated reusable widget"),
        created_by: Keyword.get(opts, :created_by)
      })
      |> insert_or_rollback()

      item
      |> DashboardLibraryItem.changeset(%{
        latest_version: next_version,
        updated_by: Keyword.get(opts, :created_by)
      })
      |> update_or_rollback()
    end)
  end

  defp fetch_library_item_for_update(organization_id, mission_id, item_id) do
    DashboardLibraryItem
    |> where(
      [item],
      item.dashboard_library_item_id == ^item_id and item.organization_id == ^organization_id and
        item.mission_id == ^mission_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %DashboardLibraryItem{} = item -> item
      nil -> Repo.rollback(:dashboard_library_item_not_found)
    end
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, struct} -> struct
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, struct} -> struct
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp document_library_consumers(document, item) do
    Enum.flat_map(document.placements, &library_consumer(&1, document, item))
  end

  defp library_consumer(placement, document, item) do
    if placement.library_widget_id == item.dashboard_library_item_id do
      [
        %{
          dashboard_id: document.dashboard_id,
          dashboard_name: document.name,
          placement_id: placement.placement_id,
          version: placement.library_version,
          latest_version: item.latest_version,
          update_available?: placement.library_version < item.latest_version
        }
      ]
    else
      []
    end
  end

  defp share_expiration(opts) do
    case Keyword.get(opts, :expires_in_hours) do
      hours when is_integer(hours) and hours > 0 ->
        DateTime.add(DateTime.utc_now(), hours * 60 * 60, :second)

      _none ->
        nil
    end
  end

  defp snapshot_data_semantics(context) do
    if is_binary(context["from"]) and is_binary(context["to"]),
      do: "frozen_time_window",
      else: "definition_at_version_current_data"
  end

  defp validate_widget_definition(widget_definition) when is_map(widget_definition) do
    widget_def = WidgetDef.from_map(widget_definition)

    validation =
      Document.validate(%Document{
        dashboard_id: "library-validation",
        organization_id: "library-validation",
        mission_id: "library-validation",
        name: "Library validation",
        placements: [
          %Placement{
            placement_id: "library-validation-placement",
            layout: %{x: 0, y: 0, w: 12, h: 8},
            widget_def: widget_def
          }
        ]
      })

    case validation do
      %ValidationResult{valid?: true} -> {:ok, WidgetDef.to_map(widget_def)}
      %ValidationResult{} -> {:error, {:invalid_library_widget, validation.errors}}
    end
  end

  defp validate_widget_definition(_widget_definition),
    do: {:error, :library_widget_definition_must_be_an_object}

  defp compatibility(widget_definition) do
    %{
      "widget_type_id" =>
        widget_definition[:widget_type_id] || widget_definition["widget_type_id"],
      "widget_type_version" =>
        widget_definition[:widget_type_version] || widget_definition["widget_type_version"],
      "binding_source" => get_in(widget_definition, [:binding, :source])
    }
  end

  defp resolve_placement(
         document,
         %Placement{
           content_kind: :library,
           library_widget_id: item_id,
           library_version: version
         } = placement
       )
       when is_binary(item_id) and is_integer(version) do
    case fetch_library_version(
           document.organization_id,
           document.mission_id,
           item_id,
           version
         ) do
      {:ok, library_version} ->
        widget_def =
          library_version.widget_definition
          |> WidgetDef.from_map()
          |> apply_library_overrides(placement.overrides)

        %Placement{placement | widget_def: widget_def}

      {:error, :dashboard_library_version_not_found} ->
        %Placement{
          placement
          | widget_def: %WidgetDef{
              widget_type_id: "unavailable_library_reference",
              widget_type_version: 1,
              title: "Unavailable library item",
              binding: %{source: :telemetry, observables: [], overlays: []},
              options: %{}
            }
        }
    end
  end

  defp resolve_placement(_document, placement), do: placement

  defp validate_playlist_dashboards(organization_id, mission_id, dashboard_ids)
       when is_list(dashboard_ids) and dashboard_ids != [] do
    available_ids =
      organization_id
      |> DocumentStore.list_dashboard_summaries(mission_id)
      |> Enum.map(& &1.dashboard_id)
      |> MapSet.new()

    if Enum.all?(dashboard_ids, &MapSet.member?(available_ids, &1)),
      do: :ok,
      else: {:error, :playlist_contains_unknown_dashboard}
  end

  defp validate_playlist_dashboards(_organization_id, _mission_id, _dashboard_ids),
    do: {:error, :playlist_requires_dashboard}

  defp validate_document_scope(%Document{} = document, organization_id, mission_id) do
    if document.organization_id == organization_id and document.mission_id == mission_id,
      do: :ok,
      else: {:error, :dashboard_scope_mismatch}
  end

  defp apply_library_overrides(%WidgetDef{} = widget_def, overrides) when is_map(overrides) do
    %WidgetDef{
      widget_def
      | title: map_value(overrides, :title) || widget_def.title,
        binding: Map.merge(widget_def.binding, map_value(overrides, :binding) || %{}),
        options: Map.merge(widget_def.options, map_value(overrides, :options) || %{})
    }
  end

  defp apply_library_overrides(%WidgetDef{} = widget_def, _overrides), do: widget_def

  defp map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
