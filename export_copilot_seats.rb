# frozen_string_literal: true

# export_copilot_seats.rb
#
# Exports GitHub Copilot Enterprise seat assignments and billing metrics
# for an organization or enterprise using the official GitHub REST API.
#
# Requirements:
#   gem install octokit
#
# Usage:
#   GITHUB_TOKEN=<your_pat> ORG=<org_name> ruby export_copilot_seats.rb
#
# The personal access token must have the `manage_billing:copilot` scope
# (and, for enterprise-level endpoints, `read:enterprise`).
#
# Output: copilot_seats.json  (seat assignments)
#         copilot_billing.json (billing summary)

require "octokit"
require "json"

TOKEN = ENV.fetch("GITHUB_TOKEN") do
  abort "ERROR: GITHUB_TOKEN environment variable is not set."
end

ORG = ENV.fetch("ORG") do
  abort "ERROR: ORG environment variable is not set."
end

client = Octokit::Client.new(access_token: TOKEN)
client.auto_paginate = true

# ---------------------------------------------------------------------------
# 1. Billing summary
# ---------------------------------------------------------------------------
puts "Fetching Copilot billing summary for org '#{ORG}'..."
billing = client.get("/orgs/#{ORG}/copilot/billing")
File.write("copilot_billing.json", JSON.pretty_generate(billing.to_h))
puts "  -> copilot_billing.json written (#{billing.to_h.keys.length} top-level keys)"

# ---------------------------------------------------------------------------
# 2. Seat assignments (paginated)
# ---------------------------------------------------------------------------
puts "Fetching Copilot seat assignments for org '#{ORG}'..."
seats_response = client.get("/orgs/#{ORG}/copilot/billing/seats", per_page: 100)

# Octokit auto-pagination fills `seats_response` as an array when the endpoint
# returns a top-level array, but the Copilot seats endpoint wraps results in
# { "total_seats": N, "seats": [...] }.  We handle both shapes below.
all_seats =
  if seats_response.respond_to?(:seats)
    seats_response.seats
  elsif seats_response.is_a?(Array)
    seats_response
  else
    []
  end

# Manual pagination fallback when auto_paginate cannot follow the envelope.
total_reported = seats_response.respond_to?(:total_seats) ? seats_response.total_seats.to_i : 0
if total_reported > 0 && all_seats.length < total_reported
  page = 1
  all_seats = []
  loop do
    page_data = client.get("/orgs/#{ORG}/copilot/billing/seats",
                           per_page: 100, page: page)
    batch = page_data.respond_to?(:seats) ? page_data.seats : Array(page_data)
    break if batch.empty?

    all_seats.concat(batch)
    break if all_seats.length >= total_reported

    page += 1
  end
end

File.write("copilot_seats.json", JSON.pretty_generate(all_seats.map(&:to_h)))
puts "  -> copilot_seats.json written (#{all_seats.length} seat(s))"

puts "Done."
