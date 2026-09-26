require "minitest/reporters"

reporters = [Minitest::Reporters::SpecReporter.new(print_failure_summary: true)]
if ENV["CI"] == "true"
  reporters += [
    Minitest::Reporters::JUnitReporter.new("test/tmp/artifacts/reports"),
  ]
end

Minitest::Reporters.use!(reporters)
