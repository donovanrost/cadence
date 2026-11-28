defmodule Cadence.Configuration.ConfigKindsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures
  import Cadence.ReadyProviderFixtures

  alias Cadence.Comms.{ListenClaims, TransportStore}
  alias Cadence.Control.Configuration
  alias Cadence.Management.ConfigKinds.Transport, as: TransportConfigKind
  alias Cadence.Management.Transports
  alias Cadence.Platform.ConfigurationSettings
  alias Cadence.Spacecraft.ConfigKinds.Spacecraft, as: SpacecraftKind
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.{Bulk, Overrides}
  alias Cadence.SpacecraftTypeStore

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("kinds")
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  describe "transport" do
    test "create, edit and archive keep the transport's own versions", ctx do
      [id] = apply_ops(ctx, "Add transport", [create("transport", transport_doc("Lab TCP"))])
      assert {:ok, %{version: 1, display_name: "Lab TCP"}} = fetch_transport(ctx, id)

      apply_ops(ctx, "Rename", [update("transport", id, "display_name", "Lab TCP 2")])
      assert {:ok, %{version: 2, display_name: "Lab TCP 2"}} = fetch_transport(ctx, id)

      apply_ops(ctx, "Archive", [%{kind: "transport", action: :delete, entity_id: id}])
      assert {:error, :transport_not_found} = fetch_transport(ctx, id)
      assert [%{version: 3, lifecycle_state: :archived} | _] = versions(ctx, id)
    end

    test "invalid settings are a NO-GO in preview", %{alice: alice, mission: mission} do
      doc = put_in(transport_doc("Bad")["configuration"]["port"], "not-a-port")

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(alice, mission, {:ops, [create("transport", doc)]})

      assert %{verdict: :no_go, items: [%{errors: [%{path: "configuration"}]}]} =
               Enum.find(checks, &(&1.key == "validation"))
    end

    # Comms parity (2): provider-managed transports through change sets. Validation runs the same
    # derivation an apply does, so a preview that passes applies, and stores what derive/3 shows.
    test "a provider-managed transport applies with the configuration derive/3 shows", ctx do
      provider = persist_ready_provider!(ctx.org, ctx.mission)
      doc = provider_doc(provider, "Provider downlink")

      assert {:ok, derived} = Transports.derive(ctx.org, ctx.mission, doc)
      assert derived.direction_capability == :inbound
      assert derived.summary.endpoint == "127.0.0.1:5100"

      [id] = apply_ops(ctx, "Add provider transport", [create("transport", doc)])

      assert {:ok, stored} = fetch_transport(ctx, id)
      assert stored.origin == :provider_managed
      assert stored.configuration == derived.configuration
      assert stored.mission_provider_version == provider.version
      assert stored.delivery_profile_ref == %{"id" => "delivery-cadence", "version" => 7}

      # An edit keeps the provider basis and its derived configuration.
      apply_ops(ctx, "Rename", [update("transport", id, "display_name", "Provider downlink 2")])

      assert {:ok, %{version: 2, origin: :provider_managed} = edited} = fetch_transport(ctx, id)
      assert edited.configuration == derived.configuration
    end

    test "provider-managed refusals land on their fields in preview", ctx do
      provider = persist_ready_provider!(ctx.org, ctx.mission)
      doc = provider_doc(provider, "Refused")

      for {bad, path} <- [
            {Map.delete(doc, "mission_provider_id"), "mission_provider_id"},
            {%{doc | "mission_provider_version" => provider.version + 1},
             "mission_provider_version"},
            {%{doc | "service_profile_ref" => %{"id" => "service-gone", "version" => 1}},
             "service_profile_ref"},
            {%{doc | "delivery_profile_ref" => %{"id" => "delivery-cadence", "version" => 6}},
             "delivery_profile_ref"}
          ] do
        assert {:ok, %{verdict: :no_go, checks: checks}} =
                 Configuration.preview(ctx.alice, ctx.mission, {:ops, [create("transport", bad)]})

        assert %{items: [%{errors: [%{path: ^path}]}]} =
                 Enum.find(checks, &(&1.key == "validation")),
               path
      end
    end

    # Listener guard (isolation): a provider-managed transport's derived configuration listens too
    # (provider_connects), so a host:port another mission listens on is refused in PREVIEW, like a
    # direct one, rather than passing and failing at apply.
    test "a provider-managed transport whose derived listen port another mission holds is refused",
         ctx do
      %{organization_id: other_org, mission_id: other} = configuration_mission("kinds-other")
      other_ctx = %{alice: member_scope(other_org, :member, "Bob"), mission: other}
      claimed = put_in(transport_doc("Other mission's listener")["configuration"]["port"], "5100")
      apply_ops(other_ctx, "Other mission listens", [create("transport", claimed)])

      provider = persist_ready_provider!(ctx.org, ctx.mission)
      doc = provider_doc(provider, "Provider downlink")

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [create("transport", doc)]})

      assert %{items: [%{errors: [%{path: "configuration.port", message: message}]}]} =
               Enum.find(checks, &(&1.key == "validation"))

      assert message == ListenClaims.message()

      # And at validate itself, not only through the store guard the preview's write also hits
      # (api-ops' review): the derived endpoint is what's checked.
      assert {:error, [%{path: "configuration.port", message: ^message}]} =
               TransportConfigKind.validate(
                 ctx.org,
                 ctx.mission,
                 :create,
                 "transport-x",
                 nil,
                 doc
               )

      # A direct transport on the same claimed port: the same refusal, from the same mapping.
      direct =
        "Direct"
        |> transport_doc()
        |> put_in(["configuration", "port"], "5100")
        |> Map.merge(%{"origin" => "direct", "transport_kind" => "tcp_socket"})

      assert {:error, [%{path: "configuration.port", message: ^message}]} =
               TransportConfigKind.validate(
                 ctx.org,
                 ctx.mission,
                 :create,
                 "transport-y",
                 nil,
                 direct
               )
    end
  end

  describe "archiving spacecraft (#49/#50)" do
    defmodule BusyTraffic do
      @moduledoc false
      def with_traffic(_org, _mission, ids), do: MapSet.new(ids)
      def archive_blockers(_org, _mission, _ids), do: %{}
    end

    test "deleting a spacecraft archives it: gone from lists, still found by id", ctx do
      [id] = apply_ops(ctx, "Add", [create("spacecraft", spacecraft_doc("ARCHIVE-1", 901))])

      assert [_] =
               apply_ops(ctx, "Archive", [%{kind: "spacecraft", action: :delete, entity_id: id}])

      refute Enum.any?(
               SpacecraftStore.list_spacecraft(ctx.org, ctx.mission),
               &(&1.spacecraft_id == id)
             )

      assert [%{lifecycle_state: :archived}] =
               ctx.org
               |> SpacecraftStore.list_spacecraft(ctx.mission, include_archived: true)
               |> Enum.filter(&(&1.spacecraft_id == id))

      assert {:ok, %{lifecycle_state: :archived, archived_at: %DateTime{}}} =
               SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, id)

      assert SpacecraftKind.load(ctx.org, ctx.mission, [id]) == %{}
      # Its SCID stays taken: history keeps pointing at it.
      assert %{901 => _holder} = Bulk.scid_holders(ctx.org, ctx.mission, [901])
    end

    test "archiving a spacecraft with traffic holds", ctx do
      [id] = apply_ops(ctx, "Add", [create("spacecraft", spacecraft_doc("ARCHIVE-2", 902))])
      previous = Application.get_env(:cadence, :spacecraft_traffic)
      Application.put_env(:cadence, :spacecraft_traffic, BusyTraffic)
      on_exit(fn -> Application.put_env(:cadence, :spacecraft_traffic, previous) end)

      assert {:ok, %{verdict: :hold, checks: checks}} =
               Configuration.preview(
                 ctx.alice,
                 ctx.mission,
                 {:ops, [%{kind: "spacecraft", action: :delete, entity_id: id}]}
               )

      assert %{items: [%{reason: :spacecraft_has_traffic, entity_id: ^id}]} =
               Enum.find(checks, &(&1.key == "compatibility"))
    end
  end

  describe "spacecraft and profiles" do
    test "a profile and its first spacecraft apply together", ctx do
      profile_id = "profile-" <> unique("block1")

      [^profile_id, sc_id] =
        apply_ops(ctx, "Block 1", [
          create("spacecraft_profile", profile_doc("Block 1"), profile_id),
          create("spacecraft", spacecraft_doc("EARENDIL-001", 1, {profile_id, 1}))
        ])

      assert {:ok, %{spacecraft_type_id: ^profile_id, spacecraft_type_version: 1, scid: 1}} =
               SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, sc_id)
    end

    test "a profile edit writes v2 and moves pinned spacecraft", ctx do
      %{alice: alice, mission: mission} = ctx
      {profile_id, [sc_a, sc_b]} = block(ctx, 2)
      edit = update("spacecraft_profile", profile_id, "frame_parameters.frame_size", 1279)

      assert {:ok, %{effects: [%{changes: 2, keeps: []}]}} =
               Configuration.preview(alice, mission, {:ops, [edit]})

      apply_ops(ctx, "Longer frames", [edit])

      assert {:ok, %{version: 2, frame_parameters: %{"frame_size" => 1279}}} =
               SpacecraftTypeStore.fetch_spacecraft_type(ctx.org, mission, profile_id)

      for id <- [sc_a, sc_b] do
        assert {:ok, %{spacecraft_type_version: 2}} =
                 SpacecraftStore.fetch_spacecraft(ctx.org, mission, id)
      end

      {:ok, %{head: %{revision: head}}} = Configuration.current(alice, mission)
      {:ok, %{entries: entries}} = Configuration.get_revision(alice, mission, head)
      assert Enum.map(entries, & &1.kind) == ["spacecraft_profile", "spacecraft", "spacecraft"]
    end

    test "profiles carrying the frame codec's fecf flag stay editable", ctx do
      profile_id = "profile-" <> unique("fecf")

      apply_ops(ctx, "FECF profile", [
        create("spacecraft_profile", profile_doc("FECF", %{"fecf" => true}), profile_id)
      ])

      apply_ops(ctx, "Rename", [
        update("spacecraft_profile", profile_id, "display_name", "FECF 2")
      ])

      assert {:ok, %{display_name: "FECF 2", frame_parameters: %{"fecf" => true}}} =
               SpacecraftTypeStore.fetch_spacecraft_type(ctx.org, ctx.mission, profile_id)
    end

    test "a pin must name a mission composition that exists (DECISIONS #36/#65; D3)", ctx do
      {profile_id, [sc]} = block(ctx, 1)

      for op <- [
            update("spacecraft_profile", profile_id, "composition_id", "composition-missing"),
            update("spacecraft_override", sc, "composition_id", %{
              "value" => "composition-missing",
              "reason" => "Trial"
            })
          ] do
        assert {:ok, %{verdict: :no_go, checks: checks}} =
                 Configuration.preview(ctx.alice, ctx.mission, {:ops, [op]})

        assert %{items: [%{errors: [%{message: "That mission composition doesn't exist"}]}]} =
                 Enum.find(checks, &(&1.key == "validation"))
      end
    end

    test "rollout none keeps every pin", ctx do
      {profile_id, [sc]} = block(ctx, 1)
      edit = update("spacecraft_profile", profile_id, "display_name", "Block 1b")

      apply_ops(ctx, "Rename only", [Map.put(edit, :options, %{rollout: "none"})])

      assert {:ok, %{spacecraft_type_version: 1}} =
               SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, sc)
    end

    test "with profile framing generations off, spacecraft governed by configuration review are kept",
         ctx do
      {:ok, _} =
        ConfigurationSettings.put_profile_framing_generations(ctx.org, ctx.mission, false, %{
          id: "test",
          name: "Test"
        })

      {profile_id, [sc]} = block(ctx, 1)
      {:ok, spacecraft} = SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, sc)
      governed = %{spacecraft | metadata: %{"spacecraft_configuration_revision_id" => "rev-1"}}
      {:ok, _} = SpacecraftStore.update_spacecraft(ctx.org, governed)

      edit = update("spacecraft_profile", profile_id, "frame_parameters.frame_size", 1000)

      assert {:ok, %{effects: [%{changes: 0, keeps: [%{reason: reason}]}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [edit]})

      assert reason =~ "configuration review"
    end

    test "by default (generations on, DECISIONS #45) governed spacecraft move with the profile",
         ctx do
      assert ConfigurationSettings.profile_framing_generations?(ctx.org, ctx.mission)

      {profile_id, [sc]} = block(ctx, 1)
      {:ok, spacecraft} = SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, sc)
      governed = %{spacecraft | metadata: %{"spacecraft_configuration_revision_id" => "rev-1"}}
      {:ok, _} = SpacecraftStore.update_spacecraft(ctx.org, governed)

      edit = update("spacecraft_profile", profile_id, "frame_parameters.frame_size", 1000)

      assert {:ok, %{effects: [%{changes: 1, keeps: []}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [edit]})
    end

    # C3 (fe-setup): keeps carry a code, and only reasons that bear on the paths the op changes.
    test "older pins keep their version unless rollout is all_versions", ctx do
      {profile_id, [sc_a, sc_b]} = block(ctx, 2)
      rename = update("spacecraft_profile", profile_id, "display_name", "Block 1b")
      apply_ops(ctx, "v2, no rollout", [Map.put(rename, :options, %{rollout: "none"})])

      edit = update("spacecraft_profile", profile_id, "display_name", "Block 1c")

      assert {:ok, %{effects: [%{changes: 0, keeps: keeps}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [edit]})

      assert Enum.map(keeps, & &1.code) == ["older_profile_version", "older_profile_version"]
      assert Enum.all?(keeps, &(&1.reason == "stays on v1"))

      all_versions = Map.put(edit, :options, %{rollout: "all_versions"})

      assert {:ok, %{effects: [%{changes: 2, keeps: []}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [all_versions]})

      apply_ops(ctx, "v3 to all", [all_versions])

      for id <- [sc_a, sc_b] do
        assert {:ok, %{spacecraft_type_version: 3}} =
                 SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, id)
      end
    end

    test "a governed spacecraft is listed as kept only when the op changes framing", ctx do
      {:ok, _} =
        ConfigurationSettings.put_profile_framing_generations(ctx.org, ctx.mission, false, %{
          id: "test",
          name: "Test"
        })

      {profile_id, [sc]} = block(ctx, 1)
      {:ok, spacecraft} = SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, sc)
      governed = %{spacecraft | metadata: %{"spacecraft_configuration_revision_id" => "rev-1"}}
      {:ok, _} = SpacecraftStore.update_spacecraft(ctx.org, governed)

      rename = update("spacecraft_profile", profile_id, "display_name", "Block 1b")

      assert {:ok, %{effects: [%{changes: 0, keeps: []}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [rename]})

      frame = update("spacecraft_profile", profile_id, "frame_parameters.frame_size", 1000)

      assert {:ok, %{effects: [%{changes: 0, keeps: [%{code: "framing_governed"}]}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [frame]})
    end

    test "a pin-only edit keeps a spacecraft whose override sets its catalog", ctx do
      {profile_id, [sc_a, _sc_b]} = block(ctx, 2)
      {:ok, _} = Overrides.put(ctx.org, ctx.mission, sc_a, "catalog_revision_id", "cat-own")
      edit = update("spacecraft_profile", profile_id, "composition_id", "composition-new")

      assert {:ok, %{effects: [%{changes: 1, keeps: [keep]}]}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [edit]})

      assert %{code: "catalog_override", spacecraft: %{id: ^sc_a}} = keep
    end

    test "framing and SCIDs are validated", ctx do
      %{alice: alice, mission: mission} = ctx
      {profile_id, _} = block(ctx, 1)

      assert {:error, {:invalid_op, 0, [%{path: "frame_parameters.frame_size"}]}} =
               Configuration.stage(alice, mission, %{summary: "x"}, [
                 update("spacecraft_profile", profile_id, "frame_parameters.frame_size", 5000)
               ])

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(
                 alice,
                 mission,
                 {:ops, [create("spacecraft", spacecraft_doc("Dup", 1))]}
               )

      assert %{items: [%{errors: [%{path: "scid"}]}]} =
               Enum.find(checks, &(&1.key == "validation"))
    end

    test "a profile in use can't be deleted", ctx do
      {profile_id, _} = block(ctx, 1)
      delete = %{kind: "spacecraft_profile", action: :delete, entity_id: profile_id}

      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [delete]})

      assert %{items: [%{errors: [%{message: "1 spacecraft use this profile"}]}]} =
               Enum.find(checks, &(&1.key == "validation"))
    end
  end

  # The kind's own pin rules (pin_exists, governed_rule). The legacy Spacecraft.Identity form had
  # different ones and left with host cleanup (a); these are tested here, at the kind.
  describe "spacecraft pins" do
    test "a pin names an existing, active, shared profile version", ctx do
      {profile_id, _} = block(ctx, 1)

      assert validation_errors(ctx, [
               create(
                 "spacecraft",
                 spacecraft_doc("Synthetic", 50, {"spacecraft_configuration_profile_x", 1})
               )
             ]) == [%{path: "spacecraft_type_id", message: "Choose a shared profile"}]

      assert validation_errors(ctx, [
               create("spacecraft", spacecraft_doc("Unknown", 51, {profile_id, 9}))
             ]) == [%{path: "spacecraft_type_id", message: "That profile version doesn't exist"}]

      assert validation_errors(ctx, [
               create("spacecraft", spacecraft_doc("Pinned", 52, {profile_id, 1}))
             ]) == []
    end

    test "an edit that keeps the pin isn't checked against it", ctx do
      {_profile_id, [sc]} = block(ctx, 1)
      assert validation_errors(ctx, [update("spacecraft", sc, "display_name", "SC-1b")]) == []
    end

    test "with generations off, a spacecraft governed by configuration review keeps its pin",
         ctx do
      {:ok, _} =
        ConfigurationSettings.put_profile_framing_generations(ctx.org, ctx.mission, false, %{
          id: "test",
          name: "Test"
        })

      {sc, repin} = governed_with_v2(ctx)

      assert validation_errors(ctx, [repin]) == [
               %{
                 path: "spacecraft_type_id",
                 message: "Change framing in Communications and submit it for review"
               }
             ]

      assert validation_errors(ctx, [update("spacecraft", sc, "display_name", "Renamed")]) == []
    end

    test "with generations on (DECISIONS #33/#45), a governed spacecraft may be re-pinned", ctx do
      assert ConfigurationSettings.profile_framing_generations?(ctx.org, ctx.mission)
      {_sc, repin} = governed_with_v2(ctx)
      assert validation_errors(ctx, [repin]) == []
    end

    test "the configuration review's revision id can't be changed by an edit", ctx do
      {sc, _repin} = governed_with_v2(ctx)
      edit = update("spacecraft", sc, "metadata.spacecraft_configuration_revision_id", "rev-2")

      assert validation_errors(ctx, [edit]) == [
               %{
                 path: "metadata",
                 message:
                   "spacecraft_configuration_revision_id is managed by configuration review"
               }
             ]
    end
  end

  # A spacecraft governed by configuration review on profile v1, a v2 of its profile, and the op
  # that re-pins it to v2.
  defp governed_with_v2(ctx) do
    {profile_id, [sc]} = block(ctx, 1)
    {:ok, spacecraft} = SpacecraftStore.fetch_spacecraft(ctx.org, ctx.mission, sc)
    governed = %{spacecraft | metadata: %{"spacecraft_configuration_revision_id" => "rev-1"}}
    {:ok, _} = SpacecraftStore.update_spacecraft(ctx.org, governed)

    rename = update("spacecraft_profile", profile_id, "display_name", "Block v2")
    apply_ops(ctx, "v2, no rollout", [Map.put(rename, :options, %{rollout: "none"})])

    {sc, update("spacecraft", sc, "spacecraft_type_version", 2)}
  end

  defp validation_errors(%{alice: alice, mission: mission}, ops) do
    {:ok, %{checks: checks}} = Configuration.preview(alice, mission, {:ops, ops})

    for %{key: "validation", items: items} <- checks,
        %{errors: errors} <- items,
        error <- errors,
        do: Map.take(error, [:path, :message])
  end

  defp block(ctx, count) do
    profile_id = "profile-" <> unique("block")

    spacecraft =
      for n <- 1..count,
          do: create("spacecraft", spacecraft_doc("SC-#{n}", n, {profile_id, 1}))

    [^profile_id | ids] =
      apply_ops(ctx, "Block", [
        create("spacecraft_profile", profile_doc("Block"), profile_id) | spacecraft
      ])

    {profile_id, ids}
  end

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end

  defp create(kind, document, id \\ nil) do
    %{kind: kind, action: :create, document: document}
    |> then(&if id, do: Map.put(&1, :entity_id, id), else: &1)
  end

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}

  defp fetch_transport(%{org: org, mission: mission}, id),
    do: TransportStore.fetch_transport(org, mission, id)

  defp versions(%{org: org, mission: mission}, id),
    do: TransportStore.list_transport_versions(org, mission, id)

  # What the console stages for a provider-managed transport (comms parity 2): no configuration
  # or direction, they're derived.
  defp provider_doc(provider, name),
    do: %{
      "display_name" => name,
      "origin" => "provider_managed",
      "mission_provider_id" => provider.provider_id,
      "mission_provider_version" => provider.version,
      "service_profile_ref" => %{"id" => "service-downlink", "version" => 3},
      "delivery_profile_ref" => %{"id" => "delivery-cadence", "version" => 7}
    }
end
