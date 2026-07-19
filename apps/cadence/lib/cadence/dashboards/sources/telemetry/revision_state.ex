defmodule Cadence.Dashboards.Sources.Telemetry.RevisionState do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataLinks,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    TelemetryActions,
    TelemetryRevisionSummary
  }

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  @spec resolve(
          [{Frame.t(), [Sample.t()]}],
          PlannedSourceRequest.t(),
          keyword(),
          keyword()
        ) :: {[Frame.t()], [ResolveWarning.t()]}
  def resolve(frames_with_samples, %PlannedSourceRequest{} = request, lookup_opts, opts)
      when is_list(frames_with_samples) and is_list(lookup_opts) and is_list(opts) do
    identity_ids =
      frames_with_samples
      |> Enum.flat_map(fn {_frame, samples} -> Enum.flat_map(samples, &sample_identity_ids/1) end)
      |> Enum.uniq()

    case identity_ids do
      [] ->
        {Enum.map(frames_with_samples, &elem(&1, 0)), []}

      ids ->
        states_by_id =
          ids
          |> fetch_identity_states(lookup_opts, opts)
          |> Map.new(&{&1.observation_identity_id, &1})

        frames_with_samples
        |> Enum.map(&annotate_frame(&1, states_by_id, request))
        |> then(fn annotated ->
          {
            Enum.map(annotated, &elem(&1, 0)),
            annotated |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq_by(&warning_key/1)
          }
        end)
    end
  end

  @spec dependency([Frame.t()]) :: map() | nil
  def dependency(frames) when is_list(frames) do
    dependencies =
      frames
      |> Enum.map(fn
        %Frame{meta: %{telemetry_revision_dependency: dependency}} when is_map(dependency) ->
          dependency

        _frame ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    case dependencies do
      [] ->
        nil

      [dependency] ->
        dependency

      dependencies ->
        %{
          kind: :telemetry_observation_identity_state_set,
          fingerprint:
            "telemetry-revision-set:" <>
              RuntimeCacheKey.fingerprint(dependencies),
          dependencies: dependencies
        }
    end
  end

  defp fetch_identity_states(identity_ids, lookup_opts, opts) do
    opts
    |> Keyword.get(:identity_states_fun, &TelemetryStorage.fetch_observation_identity_states/2)
    |> then(fn fetch_fun -> fetch_fun.(identity_ids, lookup_opts) end)
    |> case do
      states when is_list(states) -> states
      {:ok, states} when is_list(states) -> states
      _other -> []
    end
  end

  defp annotate_frame({%Frame{} = frame, samples}, states_by_id, request) do
    states =
      samples
      |> Enum.flat_map(&sample_identity_ids/1)
      |> Enum.uniq()
      |> Enum.map(&Map.get(states_by_id, &1))
      |> Enum.reject(&is_nil/1)

    summary = TelemetryRevisionSummary.from_identity_states(states)
    frame = put_summary(frame, summary)
    {frame, warnings(request, frame, summary)}
  end

  defp put_summary(%Frame{} = frame, %{identity_count: 0}), do: frame

  defp put_summary(%Frame{} = frame, summary) do
    warning_codes =
      frame.meta
      |> Map.get(:warning_codes, [])
      |> Kernel.++(summary.warning_codes)
      |> Enum.uniq()

    %Frame{
      frame
      | meta:
          frame.meta
          |> Map.put(:revision_state, summary)
          |> Map.put(:telemetry_revision_dependency, summary.dependency)
          |> merge_evidence(Map.get(summary, :evidence, []))
          |> Map.put(:warning_codes, warning_codes)
    }
  end

  defp warnings(_request, _frame, %{identity_count: 0}), do: []

  defp warnings(%PlannedSourceRequest{} = request, %Frame{} = frame, summary) do
    Enum.map(summary.warning_codes, fn code ->
      %ResolveWarning{
        code: code,
        severity: :warning,
        scope: :frame,
        frame_id: frame.frame_id,
        message: warning_message(code),
        details:
          summary
          |> Map.drop([:warning_codes])
          |> Map.merge(%{
            source_request_id: request.request_id,
            observable_id: frame.meta[:observable_id],
            point_id: frame.meta[:point_id]
          })
          |> put_warning_actions(request, frame.meta[:observable_id]),
        links: DataLinks.request_observable_links(request, source: :warning)
      }
    end)
  end

  defp warning_message(:conflicting_observations),
    do: "Telemetry range contains unresolved observation conflicts"

  defp warning_message(:corrected_range),
    do: "Telemetry range contains corrected observations"

  defp warning_message(:advisory_backfill),
    do: "Telemetry range contains advisory or backfilled observations"

  defp warning_message(:mixed_revisions),
    do: "Telemetry range contains multiple observation revision states"

  defp warning_message(code), do: "Telemetry range contains #{code}"

  defp put_warning_actions(details, %PlannedSourceRequest{} = request, observable_id) do
    actions =
      TelemetryActions.explore_actions(request, observable_id, [],
        source: :warning,
        action_id: "telemetry-warning-explore:#{request.request_id}:#{observable_id || "unknown"}"
      )

    existing_actions = List.wrap(Map.get(details, :actions))

    if existing_actions == [] and actions == [] do
      details
    else
      Map.put(details, :actions, merge_actions(existing_actions, actions))
    end
  end

  defp merge_actions(existing_actions, new_actions) do
    existing_actions
    |> Kernel.++(new_actions)
    |> Enum.uniq_by(fn
      %{action_id: action_id} when is_binary(action_id) -> action_id
      %{target: target, query: query} -> {target, query}
      action -> action
    end)
  end

  defp sample_identity_ids(%Sample{} = sample) do
    [
      storage_value(sample.provenance, :observation_identity_id),
      metadata_value(sample.provenance, :observation_identity_id)
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp storage_value(provenance, key) when is_map(provenance) do
    provenance
    |> metadata_value(:storage)
    |> metadata_value(key)
  end

  defp storage_value(_provenance, _key), do: nil

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp merge_evidence(meta, []) when is_map(meta), do: meta

  defp merge_evidence(meta, evidence) when is_map(meta) and is_list(evidence) do
    Map.put(
      meta,
      :evidence,
      (List.wrap(Map.get(meta, :evidence)) ++ evidence)
      |> Enum.uniq_by(&evidence_identity/1)
    )
  end

  defp evidence_identity(%{kind: kind, id: id}), do: {kind, id}
  defp evidence_identity(ref), do: ref

  defp warning_key(%ResolveWarning{} = warning) do
    {warning.code, warning.scope, warning.frame_id, warning.field_name}
  end
end
