defmodule Cadence.Governance.BindingSetStorageTest do
  @moduledoc """
  #447 (phase 4a, config-materialization-model.md §4 step 1): a binding-set version is stored as
  one content-addressed artifact per distinct configuration plus a membership list, not as the
  craft × packet cross product. `Governance.fetch_binding_set` expands it to the identical
  `BindingSet`, with the same `content_sha256` (#108), so no reader changes. api-ops' conditions
  (11-19) are pinned here: the write guard runs through the storage codec and the hash, a version
  that can't be compressed falls back to rows visibly, artifacts are insert-only and tenant-scoped,
  and a read that expands to a different hash is an error, never a different set.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Governance
  alias Cadence.Governance.{BindingSetRow, CapabilityInstanceRow}
  alias Cadence.Governance.Persistence, as: GovernancePersistence
  alias Cadence.Runtime.{BindingSetIndex, PartitionKey}
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.TestSupport.{BindingFleet, BindingSetEquivalence}

  @org "org-binding-storage"
  @mission "mission-binding-storage"
  @apids [42, 43, 44]

  # Read back through develop 7a539c784's rows path (before #447), for the 6-craft fixture.
  @golden_sha256 "819c9fe7abe59b6058d04db604500c47ee854f99e8f2de845649c13e51c31baa"

  setup do
    persist_mission_scope(@org, @mission)
    BindingFleet.persist_endpoints!(@org, @mission, 12)
    :ok
  end

  describe "a fleet version reads back identical (#108)" do
    test "the 6-craft version hashes as develop's rows read-back did" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      assert {:ok, read} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)
      assert BindingSet.content_sha256(read) == @golden_sha256
    end

    test "the membership form reads back equal to the same content stored as rows" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 2, 6))
      assert :ok = persist_as_rows(fleet("fleet", 1, 6))

      {:ok, membership} = Governance.fetch_binding_set(@org, @mission, "fleet", 2)
      {:ok, rows} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)

      assert storage_form("fleet", 2) == "membership"
      assert storage_form("fleet", 1) == "rows"
      assert %{membership | version: 1} == rows

      assert BindingSet.content_sha256(%{membership | version: 1}) ==
               BindingSet.content_sha256(rows)
    end
  end

  describe "storage" do
    test "one artifact per distinct configuration, one member per craft, no cross product" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      # 5 craft share a configuration; sc-1 handles one APID fewer; one mission-scoped instance.
      assert count("governed_binding_artifacts") == 3
      assert count("governed_binding_set_members") == 7
      assert instance_rows("fleet", 1) == 0
    end

    test "a bigger fleet writes no more statements than a small one" do
      small = statements(fn -> Governance.persist_binding_set(@org, fleet("small", 1, 3)) end)
      large = statements(fn -> Governance.persist_binding_set(@org, fleet("large", 1, 12)) end)

      assert large == small
    end

    test "a second version with the same configurations writes no new artifact" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 2, 6))

      assert count("governed_binding_artifacts") == 3
      assert count("governed_binding_set_members") == 14
    end
  end

  # #533 reverted the first landing of this storage because a stored set no longer expanded to
  # what it hashed as: a packet definition under its (mission, id, version) was rewritten after a
  # set referenced it. #534 made that key immutable. These pin the rule where it matters here, so a
  # regression fails in this file, not in a catalog-move apply.
  describe "a stored version cannot move under its packet definitions (#533, #534)" do
    test "another content under the same packet key is refused and the stored set still expands identical" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      {:ok, before} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)

      changed =
        PacketDefinition.new(%{
          organization_id: @org,
          mission_id: @mission,
          packet_definition_id: "hk-42",
          packet_name: "HK42",
          apid: 42,
          version: 1,
          fields: [
            %{
              field_id: "counter",
              name: "counter",
              offset_bits: 0,
              size_bits: 32,
              data_type: :uint
            }
          ]
        })

      assert {:error, {:packet_definition_content_changed, "hk-42", 1}} =
               Governance.persist_packet_definition(@org, changed)

      {:ok, after_attempt} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)
      assert after_attempt == before
      assert BindingSet.content_sha256(after_attempt) == @golden_sha256
    end

    test "a later version with other content takes the next packet version and leaves the first byte-identical" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      {:ok, first} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)

      wider =
        PacketDefinition.new(%{
          organization_id: @org,
          mission_id: @mission,
          packet_definition_id: "hk-42",
          packet_name: "HK42",
          apid: 42,
          version: 2,
          fields: [
            %{
              field_id: "counter",
              name: "counter",
              offset_bits: 0,
              size_bits: 32,
              data_type: :uint
            }
          ]
        })

      assert {:ok, _} = Governance.persist_packet_definition(@org, wider)

      assert {:ok, _} =
               Governance.persist_binding_set(
                 @org,
                 fleet("fleet", 2, 6, packet_version: %{42 => 2})
               )

      {:ok, again} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)
      assert again == first
      assert BindingSet.content_sha256(again) == @golden_sha256

      {:ok, second} = Governance.fetch_binding_set(@org, @mission, "fleet", 2)
      refute BindingSet.content_sha256(second) == @golden_sha256
    end
  end

  describe "the equivalence verifier (#447)" do
    test "is on for every test, and every persist is read back and compared with its rows" do
      assert Application.get_env(:cadence, :binding_set_storage_verifier) == BindingSetEquivalence
      assert Application.get_env(:cadence, :binding_set_storage_raise_on_fallback) == true

      set = fleet("fleet", 1, 6)
      assert {:ok, _} = Governance.persist_binding_set(@org, set)
      assert :ok = BindingSetEquivalence.verify(%{set | organization_id: @org})
    end

    test "raises when the stored version is not what the set expands to as rows" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      other = %{fleet("fleet", 1, 5) | organization_id: @org}

      assert_raise RuntimeError, ~r/different set than its rows/, fn ->
        BindingSetEquivalence.verify(other)
      end
    end
  end

  describe "the reference is a real rows write (ground-scale, #1013)" do
    test "a duplicate rule id: the rows write keeps the first, and so does membership" do
      base = fleet("dup", 1, 3)
      [first_rule | _] = base.rules
      # A second rule with the same id but another priority: validation checks rules one by one,
      # so it reaches storage; the old insert is ON CONFLICT DO NOTHING, so the first stays. (A
      # duplicate instance id is refused earlier, `duplicate_capability_instance_id`.)
      dup_rule = %{first_rule | priority: 7}
      duplicated = %{base | rules: base.rules ++ [dup_rule]}

      assert :ok = persist_as_rows(%{duplicated | version: 1, binding_set_id: "dup-rows"})
      assert {:ok, _} = Governance.persist_binding_set(@org, duplicated)
      assert storage_form("dup", 1) == "membership"

      {:ok, by_rows} = Governance.fetch_binding_set(@org, @mission, "dup-rows", 1)
      {:ok, by_membership} = Governance.fetch_binding_set(@org, @mission, "dup", 1)

      # The duplicates are gone from the rows version; membership holds exactly what it holds.
      assert length(by_rows.rules) == length(base.rules)
      assert length(by_rows.capability_instances) == length(base.capability_instances)
      assert length(duplicated.rules) == length(base.rules) + 1
      assert %{by_membership | binding_set_id: "dup-rows"} == by_rows

      assert BindingSet.content_sha256(%{by_membership | binding_set_id: "dup-rows"}) ==
               BindingSet.content_sha256(by_rows)

      assert Enum.find(by_membership.rules, &(&1.binding_rule_id == first_rule.binding_rule_id)).priority ==
               first_rule.priority
    end
  end

  describe "a set written without an organization (ground-scale, #1013)" do
    test "storage infers it from the mission and writes membership; the verifier checks it" do
      unscoped = fleet("inferred", 1, 3, organization?: false)
      assert unscoped.organization_id == nil

      assert {:ok, _} = Governance.persist_binding_set(unscoped)
      assert storage_form("inferred", 1) == "membership"

      # The Replay reader's read (mission only) and the organization-named one agree with the rows.
      assert {:ok, a} = Governance.fetch_binding_set(@mission, "inferred", 1)
      assert {:ok, b} = Governance.fetch_binding_set(@org, @mission, "inferred", 1)
      assert a == b
      assert :ok = BindingSetEquivalence.verify(unscoped)
    end
  end

  describe "the member digest (#450, commanding)" do
    alias Cadence.Governance.BindingSetStorage

    test "a membership version stores its member count and members hash, a rows version neither" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      assert :ok = persist_as_rows(fleet("fleet", 2, 6))

      membership = version_row("fleet", 1)
      rows = version_row("fleet", 2)

      assert membership.member_count == 7
      assert is_binary(membership.members_sha256)

      assert BindingSetStorage.stored_members_digest(membership) ==
               %{member_count: membership.member_count, members_sha256: membership.members_sha256}

      assert {rows.member_count, rows.members_sha256} == {nil, nil}
    end

    test "a member added after the version was written changes the recomputed hash and count" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      row = version_row("fleet", 1)
      stored = %{member_count: row.member_count, members_sha256: row.members_sha256}
      assert BindingSetStorage.stored_members_digest(row) == stored

      %{rows: [[sha]]} =
        Repo.query!("SELECT artifact_sha256 FROM governed_binding_set_members LIMIT 1")

      # Insert is allowed (a trigger refuses update and delete); admission is what refuses this.
      {1, _} =
        Repo.insert_all("governed_binding_set_members", [
          %{
            binding_set_row_id: row.id,
            organization_id: @org,
            mission_id: @mission,
            artifact_sha256: sha,
            source_endpoint_ref: endpoint(11),
            inserted_at: DateTime.utc_now()
          }
        ])

      after_insert = BindingSetStorage.stored_members_digest(row)
      refute after_insert.members_sha256 == stored.members_sha256
      assert after_insert.member_count == stored.member_count + 1
    end

    test "the digest cannot be changed after the version is written" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      assert_raise Postgrex.Error, ~r/immutable/, fn ->
        Repo.query!(
          "UPDATE governed_binding_sets SET members_sha256 = 'x' WHERE binding_set_id = 'fleet'"
        )
      end
    end

    test "a membership version without its digest, or a rows version with one, is refused" do
      assert_raise Postgrex.Error, ~r/governed_binding_sets_storage_form/, fn ->
        Repo.query!("""
        INSERT INTO governed_binding_sets (mission_id, organization_id, binding_set_id, version, storage_form, content_sha256, inserted_at)
        VALUES ('#{@mission}', '#{@org}', 'bare', 1, 'membership', 'abc', now())
        """)
      end
    end
  end

  describe "selection (#38)" do
    test "a frame on one craft's endpoint selects only that craft's instances" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      {:ok, read} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)

      for n <- 1..6 do
        selected =
          BindingSetIndex.select(read, %PartitionKey{
            affinity: :source_endpoint,
            value: endpoint(n)
          })

        refs = selected.capability_instances |> Enum.map(& &1.source_endpoint_ref) |> Enum.uniq()

        assert Enum.sort(refs, &(is_nil(&1) or &1 <= &2)) |> Enum.reject(&is_nil/1) == [
                 endpoint(n)
               ]

        for rule <- selected.rules,
            ref = BindingRule.source_endpoint_ref(rule),
            do: assert(ref == endpoint(n))
      end
    end
  end

  describe "the guard" do
    # Domain: a fallback is a bug, so today's shapes must never take it.
    test "today's generator shapes never fall back: fleet, a canary override, mission-scoped" do
      ref = make_ref()

      :telemetry.attach(
        inspect(ref),
        [:cadence, :governance, :binding_set_storage, :fallback],
        fn _event, _measurements, metadata, pid -> send(pid, {:fallback, metadata}) end,
        self()
      )

      on_exit(fn -> :telemetry.detach(inspect(ref)) end)

      for {id, craft} <- [{"one", 1}, {"canary", 2}, {"fleet", 12}] do
        assert {:ok, _} = Governance.persist_binding_set(@org, fleet(id, 1, craft))
        assert storage_form(id, 1) == "membership"
      end

      refute_received {:fallback, _metadata}
    end

    test "a version whose endpoint appears outside the four known fields is stored as rows, and raises under test unless asked not to" do
      # The suite raises on a fallback (config/test.exs); this test is about the fallback itself.
      Application.put_env(:cadence, :binding_set_storage_raise_on_fallback, false)

      on_exit(fn ->
        Application.put_env(:cadence, :binding_set_storage_raise_on_fallback, true)
      end)

      ref = make_ref()

      :telemetry.attach(
        inspect(ref),
        [:cadence, :governance, :binding_set_storage, :fallback],
        fn
          _event, measurements, metadata, pid -> send(pid, {:fallback, measurements, metadata})
        end,
        self()
      )

      on_exit(fn -> :telemetry.detach(inspect(ref)) end)

      odd = fleet("odd", 1, 2, packet_id: fn n -> endpoint(n) end)
      assert {:ok, _} = Governance.persist_binding_set(@org, odd)

      assert storage_form("odd", 1) == "rows"
      assert_received {:fallback, %{count: 1}, %{binding_set_id: "odd", version: 1}}
      assert {:ok, read} = Governance.fetch_binding_set(@org, @mission, "odd", 1)
      assert length(read.capability_instances) == 2 * length(@apids)
    end

    test "the same version raises under test, so no suite falls back unseen" do
      odd = fleet("odd-raise", 1, 2, packet_id: fn n -> endpoint(n) end)

      assert_raise RuntimeError, ~r/stored as rows, not membership/, fn ->
        Governance.persist_binding_set(@org, odd)
      end
    end

    test "a read whose expansion doesn't hash as stored is an error, never another set" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      # The stored hash is immutable (api-ops), so the test lifts the trigger in its own sandbox.
      Repo.query!("ALTER TABLE governed_binding_sets DISABLE TRIGGER USER")

      {1, _} =
        Repo.update_all(where(BindingSetRow, binding_set_id: "fleet"),
          set: [content_sha256: String.duplicate("0", 64)]
        )

      Repo.query!("ALTER TABLE governed_binding_sets ENABLE TRIGGER USER")

      assert {:error, :binding_set_expansion_mismatch} =
               Governance.fetch_binding_set(@org, @mission, "fleet", 1)
    end
  end

  describe "a version's storage" do
    test "its stored hash and form can't be changed after the insert" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      for set <- ["content_sha256 = 'x'", "storage_form = 'rows'"] do
        assert_raise Postgrex.Error, ~r/immutable/, fn ->
          Repo.query!("UPDATE governed_binding_sets SET #{set} WHERE binding_set_id = 'fleet'")
        end
      end
    end
  end

  describe "re-persisting a version (api-ops, #475)" do
    test "the same content writes nothing; other content is refused and changes nothing" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))
      before = {count("governed_binding_artifacts"), count("governed_binding_set_members")}

      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      assert {count("governed_binding_artifacts"), count("governed_binding_set_members")} ==
               before

      for other <- [
            fleet("fleet", 1, 7),
            fleet("fleet", 1, 6, packet_id: fn _n -> "hk-other" end)
          ] do
        assert {:error, :binding_set_version_changed} =
                 Governance.persist_binding_set(@org, other)

        assert {count("governed_binding_artifacts"), count("governed_binding_set_members")} ==
                 before
      end

      assert {:ok, read} = Governance.fetch_binding_set(@org, @mission, "fleet", 1)
      assert BindingSet.content_sha256(read) == @golden_sha256
    end

    test "a version's members can't be updated or deleted" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      for sql <- [
            "UPDATE governed_binding_set_members SET source_endpoint_ref = 'x'",
            "DELETE FROM governed_binding_set_members"
          ] do
        assert_raise Postgrex.Error, ~r/insert-only/, fn -> Repo.query!(sql) end
      end
    end
  end

  describe "artifacts" do
    test "are insert-only, and can't be deleted while a version references them" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      assert_raise Postgrex.Error, ~r/insert-only/, fn ->
        Repo.query!("UPDATE governed_binding_artifacts SET template = '{}'::jsonb")
      end

      assert_raise Postgrex.Error, fn ->
        Repo.query!("DELETE FROM governed_binding_artifacts")
      end
    end

    test "a member can't point at another tenant's artifact" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 1, 6))

      # The other tenant's own version (mission-scoped only), so only the artifact is foreign.
      persist_mission_scope("org-other", "mission-other")

      other =
        BindingSet.new(%{
          binding_set_id: "other",
          organization_id: "org-other",
          mission_id: "mission-other",
          version: 1,
          capability_instances: [
            CapabilityInstance.new(%{
              capability_instance_id: "other-mission-hk",
              family_key: :definition_bound_telemetry,
              target_scope: :mission,
              runtime_configuration: %{
                packet(7, "other-hk")
                | organization_id: "org-other",
                  mission_id: "mission-other"
              }
            })
          ]
        })

      assert {:ok, _} = Governance.persist_binding_set("org-other", other)

      %{rows: [[row_id]]} =
        Repo.query!("SELECT id FROM governed_binding_sets WHERE binding_set_id = 'other'")

      %{rows: [[sha] | _]} =
        Repo.query!(
          "SELECT artifact_sha256 FROM governed_binding_artifacts WHERE organization_id = $1",
          [@org]
        )

      assert_raise Postgrex.Error, ~r/governed_binding_set_members_artifact_fkey/, fn ->
        Repo.query!(
          "INSERT INTO governed_binding_set_members " <>
            "(binding_set_row_id, organization_id, mission_id, artifact_sha256, source_endpoint_ref, " <>
            "inserted_at) VALUES ($1, 'org-other', 'mission-other', $2, 'x', now())",
          [row_id, sha]
        )
      end
    end
  end

  describe "the dev check" do
    test "reports every stored version's hash, both forms" do
      assert {:ok, _} = Governance.persist_binding_set(@org, fleet("fleet", 2, 6))
      assert :ok = persist_as_rows(fleet("fleet", 1, 6))

      results = Governance.verify_binding_set_storage(@org, @mission)

      assert [
               %{version: 1, storage_form: "rows", ok?: true, content_sha256: rows_sha},
               %{version: 2, storage_form: "membership", ok?: true, content_sha256: sha}
             ] = Enum.sort_by(results, & &1.version)

      assert is_binary(rows_sha) and is_binary(sha)
    end
  end

  ## Fixtures

  # A fleet generation shaped like TelemetryDecom's (telemetry_decom.ex:1020-1079): per craft, one
  # instance and rule per handled APID, scoped to the craft's endpoint, plus one mission instance.
  defp fleet(binding_set_id, version, craft, opts \\ []),
    do: BindingFleet.build(@org, @mission, binding_set_id, version, craft, opts)

  defp packet(apid, id, version \\ 1) do
    # Only the tests that need a bare packet (the pin tests) build one.
    PacketDefinition.new(%{
      organization_id: @org,
      mission_id: @mission,
      packet_definition_id: id || "hk-#{apid}",
      packet_name: "HK#{apid}",
      apid: apid,
      version: version,
      fields: [
        %{
          field_id: "counter",
          name: "counter",
          offset_bits: 0,
          size_bits: if(version == 1, do: 16, else: 32),
          data_type: :uint
        }
      ]
    })
  end

  defp endpoint(n), do: BindingFleet.endpoint(n)

  # Today's write path, kept for the fallback: the same rows a version stored before #447 has.
  defp persist_as_rows(%BindingSet{} = binding_set) do
    packets =
      binding_set.capability_instances |> Enum.map(& &1.runtime_configuration) |> Enum.uniq()

    {:ok, :ok} =
      Repo.transaction(fn ->
        {:ok, _} = GovernancePersistence.persist_packet_definitions(Repo, packets)
        {:ok, row} = GovernancePersistence.persist_binding_set(Repo, binding_set)

        {:ok, _} =
          GovernancePersistence.persist_capability_instances(
            Repo,
            row,
            binding_set.capability_instances
          )

        {:ok, _} =
          GovernancePersistence.persist_binding_rules(
            Repo,
            row,
            binding_set.rules,
            binding_set.capability_instances
          )

        :ok
      end)

    :ok
  end

  defp version_row(binding_set_id, version),
    do:
      Repo.get_by!(BindingSetRow,
        mission_id: @mission,
        binding_set_id: binding_set_id,
        version: version
      )

  defp storage_form(binding_set_id, version) do
    Repo.one!(
      from(row in "governed_binding_sets",
        where: row.binding_set_id == ^binding_set_id and row.version == ^version,
        select: row.storage_form
      )
    )
  end

  defp instance_rows(binding_set_id, version) do
    Repo.aggregate(
      from(instance in CapabilityInstanceRow,
        join: set in BindingSetRow,
        on: set.id == instance.binding_set_row_id,
        where: set.binding_set_id == ^binding_set_id and set.version == ^version
      ),
      :count
    )
  end

  defp count(table), do: Repo.aggregate(from(row in table, select: 1), :count)

  # Writes to the governed binding tables, counted in this test's own process only.
  defp statements(fun) do
    ref = make_ref()
    me = self()

    :telemetry.attach(
      inspect(ref),
      [:cadence, :repo, :query],
      fn _event, _m, metadata, _ ->
        if self() == me and is_binary(metadata[:source]) and
             String.starts_with?(metadata[:source], ["governed_binding", "governed_capability"]),
           do: send(me, {:statement, metadata[:source]})
      end,
      nil
    )

    try do
      {:ok, _} = fun.()
    after
      :telemetry.detach(inspect(ref))
    end

    collect([])
  end

  defp collect(acc) do
    receive do
      {:statement, source} -> collect([source | acc])
    after
      0 -> Enum.frequencies(acc)
    end
  end
end
