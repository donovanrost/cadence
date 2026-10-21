defmodule Cadence.Management.Commanding.FleetCatalogTest do
  use Cadence.DataCase, async: false

  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.ExactCommandAuthoringFixtures
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.Persistence.JsonDocument

  setup do
    c = CommandAuthoringFixtures.fixture!()
    {:ok, activation} = Cadence.Activations.fetch_active_activation(c.org, c.mission)
    {:ok, Map.put(c, :manifest, activation.metadata["mission_model"])}
  end

  test "500 spacecraft share bounded evidence without repeating immutable model reads", c do
    last = CommandAuthoringFixtures.target!(c.org, c.mission)

    entries =
      Map.new(1..500, fn index ->
        source =
          case index do
            1 -> c.target.source_endpoint_id
            500 -> last.source_endpoint_id
            _ -> "fleet-source-#{index}"
          end

        {"spacecraft-#{index}", entry(c.manifest, [source, "fleet-backup-#{index}"])}
      end)

    activate_entries(c, entries)
    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(handler, [:cadence, :repo, :query], &__MODULE__.capture_query/4, owner)

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, catalog} =
             RequestAuthoring.load(c.scope, c.mission, %{
               "command" => c.model.commands_by_name["COMMAND_1"]
             })

    # The browser admits at most 100 groups, with at most 100 sources in each.
    assert length(catalog["target_bases"]) <= 100
    assert Enum.all?(catalog["target_bases"], &(length(&1["sources"]) <= 100))
    assert Enum.all?(catalog["target_bases"], & &1["compatible"])
    assert byte_size(Jason.encode!(catalog)) <= 131_072

    sources = Enum.flat_map(catalog["target_bases"], & &1["sources"])
    expected = Enum.flat_map(entries, fn {_id, entry} -> entry["source_endpoint_ids"] end)
    assert Enum.sort(sources) == Enum.sort(expected)
    assert length(sources) == 1000
    assert length(Enum.uniq(sources)) == 1000

    document_reads =
      drain_queries([])
      |> Enum.filter(&String.contains?(&1, "plan_document"))

    assert document_reads != []
    assert length(document_reads) <= 2

    assert {:ok, preview} =
             RequestAuthoring.preview(c.scope, c.mission, %{
               "expected_basis" => catalog["basis"]["token"],
               "source_endpoint_ref" => last.source_endpoint_id,
               "command_id" => c.model.commands_by_name["COMMAND_1"],
               "argument_values_json" => ~s({"amount":2}),
               "priority" => 3,
               "not_before" => nil,
               "expires_at" => nil
             })

    assert preview.request.mission_model_revision_id == c.model.revision_id
    assert preview.request.resolved_argument_values == %{"amount" => 2, "delay_s" => 5}
  end

  test "distinct models keep target-specific compatibility and disabled targets stay excluded",
       c do
    other = ExactCommandAuthoringFixtures.activate!(c.org, c.mission)
    {:ok, activation} = Cadence.Activations.fetch_active_activation(c.org, c.mission)
    other_manifest = activation.metadata["mission_model"]
    other_target = CommandAuthoringFixtures.target!(c.org, c.mission)

    activate_entries(c, %{
      "craft-a" => entry(c.manifest, [c.target.source_endpoint_id]),
      "craft-b" => entry(other_manifest, [other_target.source_endpoint_id]),
      "craft-disabled" => entry(c.manifest, ["disabled-source"], false)
    })

    assert {:ok, catalog} =
             RequestAuthoring.load(c.scope, c.mission, %{
               "command" => c.model.commands_by_name["COMMAND_1"]
             })

    first = basis_for(catalog, c.target.source_endpoint_id)
    second = basis_for(catalog, other_target.source_endpoint_id)
    assert first["compatible"]
    assert first["revision_id"] == c.model.revision_id
    refute second["compatible"]
    assert second["revision_id"] == other.revision_id
    refute basis_for(catalog, "disabled-source")

    assert {:ok, selected} =
             RequestAuthoring.load(c.scope, c.mission, %{
               "target" => other_target.source_endpoint_id,
               "command" => other.commands_by_name["SET_COUNTER"]
             })

    assert selected["basis"]["revision_id"] == other.revision_id
    assert basis_for(selected, other_target.source_endpoint_id)["compatible"]
    refute basis_for(selected, c.target.source_endpoint_id)["compatible"]
  end

  test "a changed manifest cannot borrow evidence from the same revision", c do
    changed = Map.put(c.manifest, "content_sha256", String.duplicate("0", 64))

    activate_entries(c, %{
      "craft-a" => entry(c.manifest, [c.target.source_endpoint_id]),
      "craft-b" => entry(changed, ["changed-source"])
    })

    assert {:error, :command_authoring_basis_unavailable} =
             RequestAuthoring.load(c.scope, c.mission, %{})
  end

  def capture_query(_event, _measurements, metadata, owner) do
    if self() == owner, do: send(owner, {:fleet_catalog_query, metadata.query})
  end

  defp drain_queries(queries) do
    receive do
      {:fleet_catalog_query, query} -> drain_queries([query | queries])
    after
      0 -> queries
    end
  end

  defp basis_for(catalog, source),
    do: Enum.find(catalog["target_bases"], &(source in &1["sources"]))

  defp activate_entries(c, entries) do
    row = Repo.get!(ActiveBindingSetRow, c.mission)

    metadata = %{
      "spacecraft_configuration_version" => 1,
      "spacecraft_configurations" => entries
    }

    Repo.update!(change(row, metadata: JsonDocument.wrap_value(metadata)))
  end

  defp entry(manifest, sources, enabled \\ true) do
    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => "catalog-fleet",
        "commanding_enabled" => enabled
      })

    %{
      "catalog_revision_id" => "catalog-fleet",
      "mission_model" => manifest,
      "commanding_enabled" => enabled,
      "source_endpoint_ids" => sources,
      "document" => document
    }
  end
end
