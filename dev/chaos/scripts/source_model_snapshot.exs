(fn ->
   # Bounded diagnostic result; never return the fleet model across the RPC boundary.
   unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
            System.get_env("POD_NAMESPACE") == "cadence-chaos",
          do: raise("Not the lab")

   {:ok, spec} = Cadence.Runtime.Missions.applied_spec("mission-earendil-demo")
   index = spec.source_runtime_bases

   legacy =
     Map.new(index.sources, fn {source, key} -> {source, Map.fetch!(index.models, key)} end)

   word_bytes = :erlang.system_info(:wordsize)

   IO.puts(
     "LAB_SOURCE_MODELS=" <>
       Jason.encode!(%{
         source_count: map_size(index.sources),
         distinct_models: map_size(index.models),
         indexed_shared_bytes: :erts_debug.size(index) * word_bytes,
         indexed_copied_bytes: :erts_debug.flat_size(index) * word_bytes,
         legacy_shared_bytes: :erts_debug.size(legacy) * word_bytes,
         legacy_copied_bytes: :erts_debug.flat_size(legacy) * word_bytes,
         spec_copied_bytes: :erts_debug.flat_size(spec) * word_bytes,
         binding_set_copied_bytes: :erts_debug.flat_size(spec.binding_set) * word_bytes,
         runtime_basis_sha256: spec.runtime_basis_sha256
       })
   )
 end).()
