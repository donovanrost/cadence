benchmark_dir = __DIR__

Code.require_file("lib/ephemeral_ingress_archive.ex", benchmark_dir)
Code.require_file("lib/ephemeral_protocol_record_archive.ex", benchmark_dir)
Code.require_file("lib/full_flow_runner.ex", benchmark_dir)

Cadence.IngressBenchmark.FullFlowRunner.run!()
