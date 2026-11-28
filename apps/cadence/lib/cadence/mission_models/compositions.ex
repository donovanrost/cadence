defmodule Cadence.MissionModels.Compositions do
  @moduledoc """
  Mission compositions (D1, #541; design docs/apogee/domain/mission-composition-design.md §1-2):
  which imported layers, at which mounts, in one tenant, and the effective revision each composes
  to.

  - **Identity.** `id/3` is `mission_model_composition:` + sha256 of
    `{org, mission, [{layer_id, mount}] sorted by mount}`, content-addressed within the tenant and
    pinned by a golden (#108).
  - **Write.** `insert_or_get/4` refuses a bad composition before anything is written: layers of
    this tenant, imported only, and #456's grammar, bounds and collision rules (`Mount.check/2`).
    Identical content returns the first row and its first creator (mms-security M1). It re-reads
    and fails closed on any scope or content mismatch (CB-2).
  - **Effective revision.** `effective_revision/5` compiles the composition's layers at their
    mounts (plus authored layers at a head, phase 3), under a transaction advisory lock, and
    links the revision. A link is per compiler version (domain, mms-security on #559): the
    effective revision is the one at the server's current compiler version, and a revision an
    older compiler made keeps its own link and its own approval, which doesn't carry forward.
    The link's version is always read from the revision row, never passed in. A revision with
    blocking diagnostics gets no link.
  - **Creator.** `created_by` keeps the actor's kind and ids only (`actor_kind`, `user_id`,
    `service_identity_id`, `system_id`, `run_by`), never a stored name: readers name people live
    (#146), and a system actor's `run_by` still counts its runner (#513).
  - **Number.** A new composition gets its mission's next short number (D2, #543), in
    `mission_model_composition_numbers`, never reused.
  - Rows are immutable by triggers in the schema baseline.
  """

  import Ecto.Query

  alias Cadence.Catalog.MissionModel.{Canonical, Compiler, CompilerResult, Layer, Mount, Revision}
  alias Cadence.MissionModels

  alias Cadence.MissionModels.{
    AuthoredHead,
    AuthoredScope,
    CompositionLayerRow,
    CompositionRow,
    EffectiveRevisionRow,
    LayerRow,
    RevisionRow
  }

  alias Cadence.Repo

  @prefix "mission_model_composition"
  # run_by is the person a system actor ran for, which #513's separation counts (mms-security,
  # domain on #559); it's an id, so it's kept under #146 too.
  @actor_keys ~w(actor_kind user_id service_identity_id system_id run_by)

  @type layer_ref :: %{layer_id: binary(), mount: binary(), content_sha256: binary()}
  @type t :: %{
          composition_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          imported_layers: [layer_ref()],
          created_by: map()
        }

  @doc "The composition id for `layers` (`[{layer_id, mount}]`), within the tenant."
  @spec id(binary(), binary(), [{binary(), binary()}]) :: binary()
  def id(organization_id, mission_id, layers),
    do: Canonical.content_id(@prefix, {organization_id, mission_id, canonical(layers)})

  defp canonical(layers), do: Enum.sort_by(layers, fn {layer_id, mount} -> {mount, layer_id} end)

  @doc """
  The composition of `layers` (`[{layer_id, mount}]`), stored if new. `created_by` is the actor
  document of whoever composed it (an import's actor, a change set's stager, or the migration's
  system actor), stored as its kind and ids only; for identical content the first row stands.
  """
  @spec insert_or_get(binary(), binary(), [{binary(), binary()}], map()) ::
          {:ok, t()} | {:error, term()}
  def insert_or_get(organization_id, mission_id, layers, created_by)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(layers) and
             is_map(created_by) do
    layers = canonical(layers)
    composition_id = id(organization_id, mission_id, layers)
    created_by = Map.take(created_by, @actor_keys)

    with :ok <- well_formed(organization_id, mission_id, layers) do
      Repo.transaction(fn ->
        insert(organization_id, mission_id, composition_id, layers, created_by)
        read_back(organization_id, mission_id, composition_id, layers)
      end)
    end
  end

  defp read_back(organization_id, mission_id, composition_id, layers) do
    case fetch(organization_id, mission_id, composition_id) do
      {:ok, composition} -> same_or_rollback(composition, layers)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # CB-2: what was read back must be exactly what was asked for, in this tenant.
  defp same_or_rollback(composition, layers) do
    if Enum.map(composition.imported_layers, &{&1.layer_id, &1.mount}) == layers,
      do: composition,
      else: Repo.rollback({:mission_model_composition_mismatch, composition.composition_id})
  end

  defp insert(organization_id, mission_id, composition_id, layers, created_by) do
    now = DateTime.utc_now()

    scope = %{
      organization_id: organization_id,
      mission_id: mission_id,
      composition_id: composition_id
    }

    {inserted, _rows} =
      Repo.insert_all(
        CompositionRow,
        [Map.merge(scope, %{created_by: created_by, inserted_at: now})],
        on_conflict: :nothing,
        conflict_target: [:organization_id, :mission_id, :composition_id]
      )

    rows =
      layers
      |> Enum.with_index()
      |> Enum.map(fn {{layer_id, mount}, position} ->
        Map.merge(scope, %{layer_id: layer_id, mount: mount, position: position})
      end)

    Repo.insert_all(CompositionLayerRow, rows, on_conflict: :nothing)
    if inserted == 1, do: number(organization_id, mission_id, composition_id)
  end

  # D2 (#543): a NEW composition's per-mission short number, never reused (an existing one keeps
  # the number it has). Max + 1 under a per-mission lock with its own key prefix, so two new
  # compositions can't take the same one.
  defp number(organization_id, mission_id, composition_id) do
    lock(["mission_model_composition_number", organization_id, mission_id])

    Repo.query!(
      """
      INSERT INTO mission_model_composition_numbers
        (organization_id, mission_id, composition_id, number, inserted_at)
      SELECT $1::text, $2::text, $3::text, COALESCE(MAX(number), 0) + 1, now()
        FROM mission_model_composition_numbers
       WHERE organization_id = $1::text AND mission_id = $2::text
      ON CONFLICT (organization_id, mission_id, composition_id) DO NOTHING
      """,
      [organization_id, mission_id, composition_id]
    )
  end

  # Refused before anything is written (mms-security): every layer is this tenant's and imported,
  # and the mounts pass #456's grammar, bounds and collision rules.
  defp well_formed(organization_id, mission_id, layers) do
    ids = Enum.map(layers, &elem(&1, 0))

    with :ok <- distinct(ids),
         {:ok, loaded} <- tenant_layers(organization_id, mission_id, ids),
         :ok <- imported_only(loaded),
         :ok <- Mount.check(loaded, Map.new(layers)) do
      :ok
    else
      {:error, reason} -> {:error, {:mission_model_composition_invalid, reason}}
    end
  end

  defp distinct(ids) do
    cond do
      ids == [] -> {:error, :no_layers}
      length(Enum.uniq(ids)) != length(ids) -> {:error, :duplicate_layer}
      true -> :ok
    end
  end

  defp tenant_layers(organization_id, mission_id, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn layer_id, {:ok, acc} ->
      case MissionModels.fetch_layer(organization_id, mission_id, layer_id) do
        {:ok, layer} -> {:cont, {:ok, [layer | acc]}}
        {:error, _reason} -> {:halt, {:error, {:unknown_layer, layer_id}}}
      end
    end)
    |> case do
      {:ok, layers} -> {:ok, Enum.reverse(layers)}
      error -> error
    end
  end

  defp imported_only(layers) do
    case Enum.find(layers, &(&1.layer_kind != :imported)) do
      nil -> :ok
      layer -> {:error, {:not_imported, layer.layer_id}}
    end
  end

  @doc "A stored composition, with each layer's mount and content digest, in mount order."
  @spec fetch(binary(), binary(), binary()) :: {:ok, t()} | {:error, :composition_not_found}
  def fetch(organization_id, mission_id, composition_id) do
    case Repo.get_by(CompositionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           composition_id: composition_id
         ) do
      nil -> {:error, :composition_not_found}
      %CompositionRow{} = row -> {:ok, view(row, layer_refs(row))}
    end
  end

  @doc "The composition that names `revision_id` (its link; unique on the revision, M2)."
  @spec for_revision(binary(), binary(), binary()) :: {:ok, t()} | {:error, :not_found}
  def for_revision(organization_id, mission_id, revision_id) do
    EffectiveRevisionRow
    |> where(
      [link],
      link.organization_id == ^organization_id and link.mission_id == ^mission_id and
        link.revision_id == ^revision_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      link ->
        case fetch(organization_id, mission_id, link.composition_id) do
          {:ok, composition} -> {:ok, composition}
          {:error, _missing} -> {:error, :not_found}
        end
    end
  end

  defp layer_refs(%CompositionRow{} = row) do
    from(layer in CompositionLayerRow,
      join: stored in LayerRow,
      on: stored.layer_id == layer.layer_id,
      where:
        layer.organization_id == ^row.organization_id and layer.mission_id == ^row.mission_id and
          layer.composition_id == ^row.composition_id,
      order_by: [asc: layer.position],
      select: %{
        layer_id: layer.layer_id,
        mount: layer.mount,
        content_sha256: stored.content_sha256
      }
    )
    |> Repo.all()
  end

  defp view(%CompositionRow{} = row, layers) do
    %{
      composition_id: row.composition_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      imported_layers: layers,
      created_by: row.created_by
    }
  end

  @doc """
  The effective revision of `composition_id` at `authored_head` (nil: no authored layer; else a
  recorded version of the mission's authored layer, P3 M1 #451), at the server's current compiler
  version: that version's existing link as-is; otherwise the composition's layers compiled at
  their mounts with the authored head last (never mounted), the revision
  written as today, and the link. Under a transaction advisory lock on the composition and head,
  so concurrent calls compile once (api-ops). A revision with blocking diagnostics gets no link:
  `{:error, {:mission_model_composition_invalid, codes}}`.

  `compiled:` is the caller's own compile of exactly these layers at these mounts (an import's),
  used instead of compiling them again.
  """
  @spec effective_revision(binary(), binary(), binary(), binary() | nil, keyword()) ::
          {:ok, binary()} | {:error, term()}
  def effective_revision(organization_id, mission_id, composition_id, authored_head, opts \\ [])

  def effective_revision(organization_id, mission_id, composition_id, head, opts)
      when is_nil(head) or is_binary(head) do
    Repo.transaction(fn ->
      advisory_lock(organization_id, mission_id, composition_id, head)

      case link(organization_id, mission_id, composition_id, head, Compiler.compiler_version()) do
        %EffectiveRevisionRow{revision_id: revision_id} -> revision_id
        nil -> compile_and_link(organization_id, mission_id, composition_id, head, opts)
      end
    end)
  end

  defp compile_and_link(organization_id, mission_id, composition_id, head, opts) do
    with :ok <- recorded_head(organization_id, mission_id, head),
         {:ok, composition} <- fetch(organization_id, mission_id, composition_id),
         {:ok, %CompilerResult{revision: revision}} <- compile(composition, head, opts),
         :ok <- usable(revision) do
      write_link(composition, head, revision.revision_id)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Only a recorded version of the mission's authored layer is a head (P3 M1, #451): an
  # unrecorded layer id never compiles into something a craft could run.
  defp recorded_head(_organization_id, _mission_id, nil), do: :ok

  defp recorded_head(organization_id, mission_id, head) do
    if MapSet.member?(AuthoredHead.recorded(organization_id, mission_id, [head]), head),
      do: :ok,
      else: {:error, :authored_head_not_recorded}
  end

  # A 64-bit key from sha256, so unrelated compositions rarely wait on each other (api-ops).
  defp advisory_lock(organization_id, mission_id, composition_id, head),
    do:
      lock([
        "mission_model_effective_revision",
        organization_id,
        mission_id,
        composition_id,
        head || ""
      ])

  defp lock(parts) do
    <<key::signed-64, _rest::binary>> = :crypto.hash(:sha256, Enum.join(parts, <<0>>))
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])
  end

  defp link(organization_id, mission_id, composition_id, head, compiler_version) do
    EffectiveRevisionRow
    |> where(
      [link],
      link.organization_id == ^organization_id and link.mission_id == ^mission_id and
        link.composition_id == ^composition_id and link.compiler_version == ^compiler_version
    )
    |> at_head(head)
    |> Repo.one()
  end

  defp at_head(query, nil), do: where(query, [link], is_nil(link.authored_head))
  defp at_head(query, head), do: where(query, [link], link.authored_head == ^head)

  # The composition's imported layers at their mounts, then the authored head last: an authored
  # layer is never mounted, it addresses the composed tree (Mount, #444).
  defp compile(composition, nil, opts) do
    layer_ids = Enum.map(composition.imported_layers, & &1.layer_id)
    mounts = Map.new(composition.imported_layers, &{&1.layer_id, &1.mount})

    if reusable?(Keyword.get(opts, :compiled), layer_ids, mounts),
      do: {:ok, Keyword.fetch!(opts, :compiled)},
      else:
        MissionModels.compose(composition.organization_id, composition.mission_id, layer_ids,
          mounts: mounts
        )
  end

  # At a head: the imported layers at their mounts, then the head's declarations scoped to this
  # composition (M2, AuthoredScope), last and unmounted. The revision still names the head's id.
  defp compile(composition, head, _opts) do
    %{organization_id: org, mission_id: mission} = composition
    imported = Enum.map(composition.imported_layers, & &1.layer_id)
    mounts = Map.new(composition.imported_layers, &{&1.layer_id, &1.mount})

    with {:ok, layers} <- fetch_layers(org, mission, imported),
         {:ok, authored} <- MissionModels.fetch_layer(org, mission, head),
         {:ok, base} <- base_command_plan(composition) do
      MissionModels.compile_layers(
        layers ++ [AuthoredScope.for_composition(authored, composition.composition_id)],
        mounts: mounts,
        command_plan: base
      )
    end
  end

  # The command plan of the composition's base at this compiler version: a head reuses it (option
  # B, #451). A head needs a current-compiler base (the v1 rule): none is a refusal.
  defp base_command_plan(composition) do
    %{organization_id: org, mission_id: mission, composition_id: id} = composition

    case link(org, mission, id, nil, Compiler.compiler_version()) do
      %EffectiveRevisionRow{revision_id: base} ->
        MissionModels.fetch_plan(org, mission, base, :command)

      nil ->
        {:error, :monitoring_needs_current_compile}
    end
  end

  @doc """
  The blocking diagnostics `composition_id` would have compiled with `authored` (a candidate
  authored layer, scoped to the composition) last: compiled in memory, nothing written or linked.
  For a monitoring preview's checks (P3 M2, #451).
  """
  @spec check_at(binary(), binary(), binary(), Layer.t()) :: {:ok, [map()]} | {:error, term()}
  def check_at(organization_id, mission_id, composition_id, %Layer{} = authored) do
    with {:ok, composition} <- fetch(organization_id, mission_id, composition_id),
         imported = Enum.map(composition.imported_layers, & &1.layer_id),
         mounts = Map.new(composition.imported_layers, &{&1.layer_id, &1.mount}),
         {:ok, layers} <- fetch_layers(organization_id, mission_id, imported),
         {:ok, %CompilerResult{} = result} <-
           Compiler.compile(
             layers ++ [AuthoredScope.for_composition(authored, composition_id)],
             mounts: mounts
           ) do
      {:ok, result |> blocking() |> Enum.map(&Map.take(&1, [:code, :semantic_id, :message]))}
    end
  end

  defp blocking(%CompilerResult{revision: revision, plans: plans}) do
    plan_diagnostics = plans |> Map.values() |> Enum.flat_map(& &1.diagnostics)

    (revision.diagnostics ++ plan_diagnostics)
    |> Enum.filter(&(&1.severity == :error))
    |> Enum.uniq_by(&{&1.code, &1.semantic_id})
  end

  defp fetch_layers(org, mission, layer_ids) do
    Enum.reduce_while(layer_ids, {:ok, []}, fn layer_id, {:ok, acc} ->
      case MissionModels.fetch_layer(org, mission, layer_id) do
        {:ok, layer} -> {:cont, {:ok, acc ++ [layer]}}
        {:error, reason} -> {:halt, {:error, {layer_id, reason}}}
      end
    end)
  end

  # Only an unmounted single-layer compile of the same layer is the same compile (#456: one
  # layer at '/' is byte-identical), so an import's own result can stand in.
  defp reusable?(%CompilerResult{revision: %Revision{layer_ids: [id]}}, [id], mounts),
    do: mounts == %{id => "/"}

  defp reusable?(_compiled, _layer_ids, _mounts), do: false

  defp usable(%Revision{} = revision) do
    if Revision.valid?(revision),
      do: :ok,
      else:
        {:error,
         {:mission_model_composition_invalid,
          revision.diagnostics |> Enum.filter(&(&1.severity == :error)) |> Enum.map(& &1.code)}}
  end

  # The link's compiler version is the revision row's own (mms-security, condition 1); the
  # composite foreign key refuses any other.
  defp write_link(composition, head, revision_id) do
    %{organization_id: org, mission_id: mission, composition_id: composition_id} = composition
    version = revision_compiler_version!(org, mission, revision_id)

    Repo.insert_all(
      EffectiveRevisionRow,
      [
        %{
          organization_id: org,
          mission_id: mission,
          composition_id: composition_id,
          authored_head: head,
          compiler_version: version,
          revision_id: revision_id,
          inserted_at: DateTime.utc_now()
        }
      ],
      on_conflict: :nothing
    )

    case link(org, mission, composition_id, head, version) do
      %EffectiveRevisionRow{revision_id: ^revision_id} -> revision_id
      _other -> Repo.rollback({:mission_model_effective_revision_conflict, revision_id})
    end
  end

  defp revision_compiler_version!(organization_id, mission_id, revision_id) do
    RevisionRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.revision_id == ^revision_id
    )
    |> select([r], r.compiler_version)
    |> Repo.one!()
  end
end
