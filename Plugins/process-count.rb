#!/usr/bin/env ruby
# Read-only probe: processes visible to the executing identity.
require 'json'
abort 'Expected --aelab-probe' unless ARGV == ['--aelab-probe']
output = IO.popen(['ps', '-e', '-o', 'pid='], &:read)
abort 'Cannot list processes' unless $?.success?
count = output.lines.count { |line| line.strip.match?(/\A\d+\z/) }
puts JSON.generate(version: 1, status: 'ok', summary: "#{count} visible processes", details: [
  { label: 'Process count', value: count.to_s },
  { label: 'Host ID', value: ENV.fetch('AELAB_HOST_ID', 'standalone') }
])
