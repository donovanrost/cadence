defmodule CadenceWeb.Console.DashboardImportRaceTest do
  @moduledoc "Two concurrent `keep` imports of one dashboard id (#746): the loser is answered, never raised."
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias Cadence.Dashboards.{Creation, DocumentCodec, Documents}

  setup do: authoring_draft_setup()

  defp input(c, id, overrides \\ %{}) do
    {:ok, json} =
      DocumentCodec.encode(%{
        c.document
        | dashboard_id: id,
          name: overrides[:name] || c.document.name
      })

    %{"document_json" => json, "identity" => "keep"}
  end

  # Holds each import after its id check, until both have checked: both see the id free.
  defp barrier do
    {:ok, arrived} = Agent.start_link(fn -> 0 end)

    fn ->
      Agent.update(arrived, &(&1 + 1))
      wait_for_both(arrived)
    end
  end

  defp wait_for_both(arrived) do
    if Agent.get(arrived, & &1) >= 2, do: :ok, else: Process.sleep(5) && wait_for_both(arrived)
  end

  defp import_concurrently(c, inputs) do
    hold = barrier()
    mission = c.mission.mission_id

    inputs
    |> Enum.map(fn input ->
      Task.async(fn ->
        Creation.create(c.scope, mission, %{mode: "import"}, input, after_check: hold)
      end)
    end)
    |> Enum.map(&Task.await(&1, 15_000))
  end

  test "two identical imports: one creates it, the other finds it identical", c do
    id = "race-" <> Ecto.UUID.generate()
    results = import_concurrently(c, [input(c, id), input(c, id)])

    assert [created, existing] = Enum.sort_by(results, &match?({:ok, %{existing?: true}}, &1))
    assert {:ok, %{dashboard_id: ^id, version: 1}} = created
    assert {:ok, %{dashboard_id: ^id, version: 1, existing?: true}} = existing

    assert length(Documents.list_versions(c.org.organization_id, c.mission.mission_id, id)) == 1
  end

  test "two different imports of one id: one creates it, the other is a conflict with a summary",
       c do
    id = "race-" <> Ecto.UUID.generate()
    results = import_concurrently(c, [input(c, id), input(c, id, %{name: "Another name"})])

    assert [{:ok, %{dashboard_id: ^id, version: 1}}, {:invalid, {:conflict, summary}}] =
             Enum.sort_by(results, &match?({:invalid, _}, &1))

    assert "name" in summary.fields
  end
end
