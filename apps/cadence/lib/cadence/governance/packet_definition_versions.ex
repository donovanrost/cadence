defmodule Cadence.Governance.PacketDefinitionVersions do
  @moduledoc """
  Resolves each plan packet definition's version by content (#534, domain's note §2, amendment 1),
  before a binding set is built: each instance's capability config names the version, and the
  set's hash covers it, so the version must be right before the set exists.

  For each definition (the plan decodes them all as version 1):
  - a stored version of that `(mission, packet_definition_id)` with the same content
    (`PacketDefinitionContent`) is reused;
  - otherwise it gets the next version: one past every stored version and every version already
    given in this generation.

  The accumulator carries what this generation has resolved, `%{packet_definition_id =>
  [{version, content}]}`, so one generation over several catalogs (a canary on another revision)
  gives distinct new contents distinct versions, and the same content the same one. A caller with
  a single catalog starts from `%{}`. Read-only: two generations racing to the same next version are
  caught at persist, which refuses the second (it re-resolves on retry).
  """

  import Ecto.Query

  alias Cadence.Governance.{GovernedPacketDefinitionRow, PacketDefinitionContent}
  alias Cadence.Repo
  alias Cadence.Telemetry.PacketDefinition

  @type acc :: %{binary() => [{pos_integer(), term()}]}

  @spec resolve(binary() | nil, binary(), [PacketDefinition.t()], acc()) ::
          {:ok, [PacketDefinition.t()], acc()}
  def resolve(_organization_id, mission_id, definitions, acc)
      when is_binary(mission_id) and is_list(definitions) and is_map(acc) do
    stored = stored(mission_id, definitions |> Enum.map(& &1.packet_definition_id) |> Enum.uniq())

    {resolved, acc} =
      Enum.map_reduce(definitions, acc, fn %PacketDefinition{} = definition, acc ->
        id = definition.packet_definition_id
        content = PacketDefinitionContent.of(definition)
        known = Map.get(stored, id, []) ++ Map.get(acc, id, [])
        version = same(known, content) || next(known)

        {%PacketDefinition{definition | version: version},
         Map.update(acc, id, [{version, content}], &Enum.uniq([{version, content} | &1]))}
      end)

    # Observability, and the seam #534's race test uses (api-ops' condition 3).
    :telemetry.execute(
      [:cadence, :governance, :packet_definitions, :resolved],
      %{count: length(resolved)},
      %{
        mission_id: mission_id,
        versions: Enum.map(resolved, &{&1.packet_definition_id, &1.version})
      }
    )

    {:ok, resolved, acc}
  end

  defp same(known, content),
    do:
      Enum.find_value(known, fn {version, known_content} ->
        known_content == content && version
      end)

  defp next([]), do: 1
  defp next(known), do: known |> Enum.map(&elem(&1, 0)) |> Enum.max() |> Kernel.+(1)

  # Every stored version of these definitions, with its content: one query.
  defp stored(_mission_id, []), do: %{}

  defp stored(mission_id, ids) do
    GovernedPacketDefinitionRow
    |> where([row], row.mission_id == ^mission_id and row.packet_definition_id in ^ids)
    |> preload(:field_rows)
    |> Repo.all()
    |> Enum.group_by(& &1.packet_definition_id, &{&1.version, PacketDefinitionContent.of(&1)})
  end
end
