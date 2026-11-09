defmodule Cadence.CommandGroupFixtures do
  @moduledoc false

  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.CommandReviewFixtures
  alias Cadence.ExactCommandAuthoringFixtures

  @doc "A mission with the exact-authoring catalog active and `count` commandable spacecraft."
  def setup!(count \\ 2) do
    c = CommandReviewFixtures.scope!()
    model = ExactCommandAuthoringFixtures.activate!(c.org, c.mission)

    spacecraft =
      for i <- 1..count do
        id = "sc-#{i}"

        {:ok, _} =
          Cadence.SpacecraftStore.persist_spacecraft(
            c.org,
            Cadence.Spacecraft.new(%{
              spacecraft_id: id,
              organization_id: c.org,
              mission_id: c.mission,
              display_name: "SC-#{i}"
            })
          )

        CommandAuthoringFixtures.target!(c.org, c.mission, %{
          spacecraft_id: id,
          display_name: "SC-#{i}"
        })

        id
      end

    Map.merge(c, %{ids: model.commands_by_name, spacecraft: spacecraft})
  end

  def command(c, name, args), do: %{command_id: c.ids[name], argument_values: args}

  def draft(spacecraft_ids, commands, extra \\ %{}) do
    Map.merge(
      %{
        title: "Load shed",
        targets: Enum.map(spacecraft_ids, &%{spacecraft_id: &1}),
        commands: commands,
        priority: 3
      },
      extra
    )
  end

  def actor(c), do: %{"actor_kind" => "user", "user_id" => c.scope.user.user_id}

  @doc "The digest a preflight would have shown for `draft`."
  def digest(c, draft) do
    {:ok, validated} = Validation.validate(c.org, c.mission, actor(c), draft)
    validated.digest
  end
end
