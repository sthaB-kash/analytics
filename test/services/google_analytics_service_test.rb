require "test_helper"
require "google/analytics/data/v1beta"

class GoogleAnalyticsServiceTest < ActiveSupport::TestCase
  CREDENTIALS = {
    property_id: "426706035",
    client_email: "reporter@example.iam.gserviceaccount.com",
    private_key: '-----BEGIN PRIVATE KEY-----\nMIIB\n-----END PRIVATE KEY-----\n'
  }.freeze

  test "raises when no property is configured" do
    error = assert_raises GoogleAnalyticsService::Error do
      GoogleAnalyticsService.new(credentials: CREDENTIALS.merge(property_id: nil))
    end

    assert_match "property_id", error.message
  end

  test "unescapes the newlines in a single-line service account key" do
    key = GoogleAnalyticsService.new(credentials: CREDENTIALS).send(:private_key)

    assert_not_includes key, '\n'
    assert_equal "-----BEGIN PRIVATE KEY-----", key.lines.first.chomp
  end

  test "requests page views and visitors in a single report" do
    assert_equal [ "screenPageViews", "activeUsers" ], GoogleAnalyticsService::METRICS.values
  end

  test "reports every day in the window with both metrics and the API totals" do
    travel_to Date.new(2026, 8, 26) do
      report = service_returning(
        rows: { "20260820" => [ 4535, 2037 ], "20260825" => [ 5724, 2853 ] },
        total: [ 10259, 4000 ]
      ).report

      assert_equal "2026-08-19", report[:start_date]
      assert_equal "2026-08-25", report[:end_date]
      assert_equal 10259, report[:total_page_views]
      # Not 4890: the API total counts a visitor active on two days only once.
      assert_equal 4000, report[:total_visitors]
      assert_equal 7, report[:days].length
      assert_equal({ date: "2026-08-20", page_views: 4535, visitors: 2037 }, report[:days][1])
      # Days GA omitted are filled with zeroes rather than left out.
      assert_equal({ date: "2026-08-21", page_views: 0, visitors: 0 }, report[:days][2])
    end
  end

  test "falls back to summing days when the aggregation row is missing" do
    travel_to Date.new(2026, 8, 26) do
      report = service_returning(
        rows: { "20260820" => [ 4535, 2037 ], "20260825" => [ 5724, 2853 ] },
        total: nil
      ).report

      assert_equal 10259, report[:total_page_views]
      assert_equal 4890, report[:total_visitors]
    end
  end

  private

  # Builds a service whose report call returns a stubbed GA4 response, so the
  # date filling and total handling are exercised without touching the network.
  def service_returning(rows:, total:)
    response = Google::Analytics::Data::V1beta::RunReportResponse.new(
      rows: rows.map { |date, metrics| ga_row(date, metrics) },
      totals: total.nil? ? [] : [ ga_row("RESERVED_TOTAL", total) ]
    )

    GoogleAnalyticsService.new(credentials: CREDENTIALS).tap do |service|
      service.define_singleton_method(:run_report) { |**| response }
    end
  end

  def ga_row(dimension, metrics)
    Google::Analytics::Data::V1beta::Row.new(
      dimension_values: [ { value: dimension } ],
      metric_values: metrics.map { |value| { value: value.to_s } }
    )
  end
end
