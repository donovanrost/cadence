defmodule CadenceWeb.Console.DashboardSharedViews do
  @moduledoc """
  D20 (dashboards, docs/apogee/plans/dashboards-slice6.md): a share or snapshot opened by its
  link. `{kind, share | snapshot_row, dashboard, definition (the editor outline), snapshot (the
  workspace snapshot, null when definition-only)}`. A link that stopped working answers why:
  `share_revoked`, `share_expired` or `snapshot_deleted`, each with the page's sentence.
  """

  alias Cadence.Dashboards.Document
  alias Cadence.Reads.Dashboards.{Editor, SharedViewRecords, SharedViews}

  @wire_visibility %{
    "authorized_runtime_data" => "with_data",
    "definition_only" => "definition_only"
  }

  @spec load(map(), binary(), :share | :snapshot, binary(), binary() | nil, map()) ::
          {:ok, map()} | {:error, term()}
  def load(scope, mission, kind, id, base_url, params \\ %{}) do
    org = scope.organization_id
    opts = runtime_opts(kind, params)

    case {SharedViews.load(scope, mission, kind, id, opts),
          SharedViewRecords.fetch(org, mission, kind, id)} do
      {{:ok, view}, {:ok, record}} -> {:ok, view(kind, view, record, base_url)}
      {{:error, {:invalid, details}}, _record} -> {:error, {:invalid_params, details}}
      {_refused, {:ok, record}} -> {:error, gone(kind, record)}
      {_refused, :error} -> {:error, :not_found}
    end
  end

  defp view(kind, view, record, base_url) do
    document = view.definition && view.definition.json |> Jason.decode!() |> Document.from_map()

    %{
      kind: Atom.to_string(kind),
      share: if(kind == :share, do: share_row(record, base_url)),
      snapshot_row: if(kind == :snapshot, do: snapshot_row(record, base_url)),
      dashboard: %{
        id: view.dashboard_id,
        name: view.definition && view.definition.name,
        description: view.definition && view.definition.description
      },
      definition: document && Editor.outline(document),
      snapshot: view.canvas
    }
  end

  defp gone(:share, %{revoked_at: %DateTime{} = at} = record) do
    by = record[:revoked_by]

    {:gone, :share_revoked, "Revoked#{by_name(by)} at #{stamp(at)}.",
     %{revoked_at: at, revoked_by: by && Map.take(by, [:id, :name])}}
  end

  defp gone(:share, %{expires_at: %DateTime{} = at}) do
    if DateTime.compare(at, DateTime.utc_now()) != :gt,
      do: {:gone, :share_expired, "Expired #{stamp(at)}.", %{expires_at: at}},
      else: :unavailable
  end

  defp gone(:snapshot, %{deleted_at: %DateTime{} = at, deleted_by: by}),
    do:
      {:gone, :snapshot_deleted, "Deleted#{by_name(by)} on #{Calendar.strftime(at, "%m-%d")}.",
       %{deleted_by: by && Map.take(by, [:id, :name]), deleted_at: at}}

  defp gone(_kind, _record), do: :unavailable

  # A share's live range (D5-style from/to and spacecraft_id); snapshots are frozen.
  defp runtime_opts(:share, params) do
    runtime =
      params
      |> Map.take(~w(from to spacecraft_id))
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)

    if runtime == %{}, do: [], else: [runtime: runtime]
  end

  defp runtime_opts(:snapshot, _params), do: []

  defp by_name(%{name: name}) when is_binary(name), do: " by #{name}"
  defp by_name(_unknown), do: ""

  defp stamp(at), do: Calendar.strftime(at, "%m-%d %H:%MZ")

  defp share_row(record, base_url),
    do: %{
      id: record.id,
      url: base_url && base_url <> "/shares/" <> record.id,
      data_visibility: visibility(record.data_visibility),
      state: "active",
      expires_at: record.expires_at,
      created_at: record.created_at,
      created_by: record.created_by
    }

  defp snapshot_row(record, base_url),
    do: %{
      id: record.id,
      url: base_url && base_url <> "/snapshots/" <> record.id,
      version: record.version,
      data_visibility: visibility(record.data_visibility),
      window: record.window,
      created_at: record.created_at,
      created_by: record.created_by
    }

  defp visibility(value), do: Map.get(@wire_visibility, value, value)
end
