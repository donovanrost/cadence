defmodule Cadence.Platform.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Platform.{EventBus, RootComposition}

  def child_spec(opts) do
    composition = root_composition(opts)

    %{
      id: supervisor_name(opts, composition),
      start: {__MODULE__, :start_link, [Keyword.put(opts, :root_composition, composition)]},
      type: :supervisor
    }
  end

  def start_link(opts \\ []) do
    composition = root_composition(opts)
    opts = Keyword.put(opts, :root_composition, composition)

    case supervisor_name(opts, composition) do
      nil -> Supervisor.start_link(__MODULE__, opts)
      name -> Supervisor.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def init(opts) do
    composition = root_composition(opts)

    children =
      composition.platform_children ++
        [{EventBus, event_bus_child_opts(opts, composition)}]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp event_bus_child_opts(_opts, %RootComposition{} = composition),
    do: composition.event_bus_child_opts

  defp supervisor_name(_opts, %RootComposition{} = composition),
    do: composition.platform_supervisor_name

  defp root_composition(opts) do
    case Keyword.fetch(opts, :root_composition) do
      {:ok, %RootComposition{} = composition} ->
        composition

      :error ->
        compatibility_opts =
          []
          |> copy_option(opts, :name, :platform_supervisor_name)
          |> copy_option(opts, :platform_children)
          |> copy_option(opts, :event_bus_child_opts)

        RootComposition.from_application(compatibility_opts)
    end
  end

  defp copy_option(target, source, source_key, target_key \\ nil) do
    case Keyword.fetch(source, source_key) do
      {:ok, value} -> Keyword.put(target, target_key || source_key, value)
      :error -> target
    end
  end
end
