defmodule Cadence.Governance.PacketDefinitionVersionsTest do
  @moduledoc """
  #534: a governed packet definition is immutable under `(mission, packet_definition_id, version)`.
  Its version is resolved by content before a binding set is built; persist never merges fields
  into an existing version and refuses a different content under a key; the database refuses any
  change but DECISIONS #73's identity fill. (Domain's note, amendments 1-2; api-ops' and
  ca-security's conditions.)
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Governance

  alias Cadence.Governance.{
    GovernedPacketDefinitionRow,
    PacketDefinitionContent,
    PacketDefinitionFieldRow
  }

  alias Cadence.Telemetry.PacketDefinition

  @org "org-pd-versions"
  @mission "mission-pd-versions"

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  describe "content (api-ops' condition 1)" do
    test "every column of both row schemas is content or explicitly excluded" do
      for {schema, kind} <- [
            {GovernedPacketDefinitionRow, :definition},
            {PacketDefinitionFieldRow, :field}
          ] do
        counted = PacketDefinitionContent.columns(kind) ++ PacketDefinitionContent.excluded(kind)

        assert Enum.sort(counted) == Enum.sort(schema.__schema__(:fields)),
               "#{inspect(schema)}: a column is neither content nor excluded"

        assert MapSet.disjoint?(
                 MapSet.new(PacketDefinitionContent.columns(kind)),
                 MapSet.new(PacketDefinitionContent.excluded(kind))
               )
      end
    end

    test "a definition's content equals its stored row's, and leaves out the #73 identity" do
      definition = health(["mode"], identity: true)
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, definition))

      assert PacketDefinitionContent.of(definition) == PacketDefinitionContent.of(stored_row(1))

      assert PacketDefinitionContent.of(definition) ==
               PacketDefinitionContent.of(health(["mode"]))
    end
  end

  describe "resolve (domain's note §2, amendment 1)" do
    test "nothing stored is version 1; the same content reuses; another content is the next" do
      assert {:ok, [%{version: 1}], _} = resolve([health(["mode"])])
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, health(["mode"])))

      assert {:ok, [%{version: 1}], _} = resolve([health(["mode"])])
      assert {:ok, [%{version: 2}], _} = resolve([health(["mode", "aux"])])
    end

    test "within one generation, distinct new contents get distinct versions (accumulator)" do
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, health(["mode"])))

      assert {:ok, [%{version: 2}], acc} = resolve([health(["mode", "aux"])])
      assert {:ok, [%{version: 3}], acc} = resolve([health(["mode", "flag"])], acc)
      assert {:ok, [%{version: 2}], _acc} = resolve([health(["mode", "aux"])], acc)
      assert {:ok, [%{version: 1}], _acc} = resolve([health(["mode"])], acc)
    end
  end

  describe "persist (domain's note §3)" do
    test "A then B: A's stored version hydrates byte-identically after B (ca-security 3)" do
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, health(["mode"])))
      {:ok, before} = Governance.fetch_binding_set(@org, @mission, "a", 1)

      {:ok, [b], _} = resolve([health(["mode", "aux"])])
      assert {:ok, _} = Governance.persist_binding_set(@org, set("b", 1, b))

      {:ok, again} = Governance.fetch_binding_set(@org, @mission, "a", 1)
      assert again == before
      assert BindingSet.content_sha256(again) == BindingSet.content_sha256(before)
      assert field_names(1) == ["mode"]
      assert field_names(2) == ["aux", "mode"]
    end

    test "a different content under an existing key is refused, and nothing is written" do
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, health(["mode"])))

      # Unresolved (still version 1): what a racing generation would persist.
      assert {:error, {:packet_definition_content_changed, "health", 1}} =
               Governance.persist_binding_set(@org, set("b", 1, health(["mode", "aux"])))

      assert field_names(1) == ["mode"]

      assert {:error, :binding_set_not_found} =
               Governance.fetch_binding_set(@org, @mission, "b", 1)
    end

    test "the same content again is a no-op; the #73 fill is NULL-only and moves no hash" do
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, health(["mode"])))
      {:ok, before} = Governance.fetch_binding_set(@org, @mission, "a", 1)
      assert [%{parameter_id: nil}] = stored_row(1).field_rows

      # The same content with its identity: filled once, never overwritten.
      assert {:ok, _} =
               Governance.persist_binding_set(@org, set("b", 1, health(["mode"], identity: true)))

      assert [%{parameter_id: "param:mode"}] = stored_row(1).field_rows

      other = health(["mode"], identity: true) |> put_identity("other:mode")
      assert {:ok, _} = Governance.persist_binding_set(@org, set("c", 1, other))
      assert [%{parameter_id: "param:mode"}] = stored_row(1).field_rows

      {:ok, after_fill} = Governance.fetch_binding_set(@org, @mission, "a", 1)
      assert BindingSet.content_sha256(after_fill) == BindingSet.content_sha256(before)
    end
  end

  describe "the database (ca-security 2, #116's triggers)" do
    setup do
      assert {:ok, _} = Governance.persist_binding_set(@org, set("a", 1, health(["mode"])))
      %{row: stored_row(1)}
    end

    test "a definition can't be updated or deleted", %{row: row} do
      for sql <- [
            "UPDATE governed_packet_definitions SET packet_name = 'X' WHERE id = $1",
            "UPDATE governed_packet_definitions SET apid = 7 WHERE id = $1",
            "DELETE FROM governed_packet_definitions WHERE id = $1"
          ] do
        assert_raise Postgrex.Error, ~r/immutable/, fn -> Repo.query!(sql, [row.id]) end
      end
    end

    test "a field allows exactly the #73 fill: NULL to a value, or its own value again", %{
      row: row
    } do
      [field] = row.field_rows

      refused = [
        "UPDATE governed_packet_definition_fields SET size_bits = 16 WHERE id = $1",
        "UPDATE governed_packet_definition_fields SET name = 'x' WHERE id = $1",
        "DELETE FROM governed_packet_definition_fields WHERE id = $1"
      ]

      for sql <- refused,
          do: assert_raise(Postgrex.Error, ~r/immutable/, fn -> Repo.query!(sql, [field.id]) end)

      fill =
        "UPDATE governed_packet_definition_fields SET parameter_id = 'p', qualified_name = 'q' WHERE id = $1"

      assert %{num_rows: 1} = Repo.query!(fill, [field.id])
      assert %{num_rows: 1} = Repo.query!(fill, [field.id])

      assert_raise Postgrex.Error, ~r/immutable/, fn ->
        Repo.query!(
          "UPDATE governed_packet_definition_fields SET parameter_id = 'other' WHERE id = $1",
          [field.id]
        )
      end
    end
  end

  ## Fixtures

  defp resolve(definitions, acc \\ %{}),
    do: Governance.resolve_packet_definition_versions(@org, @mission, definitions, acc)

  defp health(names, opts \\ []) do
    identity? = Keyword.get(opts, :identity, false)

    PacketDefinition.new(%{
      organization_id: @org,
      mission_id: @mission,
      packet_definition_id: "health",
      packet_name: "HEALTH",
      apid: 42,
      version: 1,
      fields:
        names
        |> Enum.sort()
        |> Enum.with_index()
        |> Enum.map(fn {name, index} ->
          %{
            field_id: "field:" <> name,
            name: name,
            offset_bits: index * 8,
            size_bits: 8,
            data_type: :uint,
            parameter_id: if(identity?, do: "param:" <> name),
            qualified_name: if(identity?, do: "/parameters/HEALTH/" <> name)
          }
        end)
    })
  end

  defp put_identity(%PacketDefinition{} = definition, parameter_id),
    do: %{definition | fields: Enum.map(definition.fields, &%{&1 | parameter_id: parameter_id})}

  defp set(id, version, %PacketDefinition{} = definition) do
    BindingSet.new(%{
      organization_id: @org,
      mission_id: @mission,
      binding_set_id: id,
      version: version,
      rules: [
        BindingRule.new(%{
          binding_rule_id: id <> "-rule",
          priority: 100,
          handler_key: :definition_bound_telemetry,
          packet_kind: :space_packet,
          apid: definition.apid,
          handler_configuration: definition
        })
      ]
    })
  end

  defp stored_row(version) do
    GovernedPacketDefinitionRow
    |> where(mission_id: @mission, packet_definition_id: "health", version: ^version)
    |> Repo.one!()
    |> Repo.preload(:field_rows)
  end

  defp field_names(version),
    do: version |> stored_row() |> Map.fetch!(:field_rows) |> Enum.map(& &1.name) |> Enum.sort()
end
