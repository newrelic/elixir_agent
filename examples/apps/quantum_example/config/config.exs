use Mix.Config

if Mix.env() != :test do
  config :quantum_example, QuantumExample.Scheduler,
    jobs: [
      {"@reboot", fn -> IO.puts("Quantum started") end},
      {"@reboot", {QuantumExample.Jobs, :do_some_work, []}},
      job_with_meaninful_name: [
        schedule: "@reboot",
        task: {QuantumExample.Jobs, :do_some_work, []}
      ]
    ]
end
