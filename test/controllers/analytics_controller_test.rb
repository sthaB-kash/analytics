require "test_helper"

class AnalyticsControllerTest < ActionDispatch::IntegrationTest
  REPORT = {
    property_id: "426706035",
    start_date: "2026-08-19",
    end_date: "2026-08-25",
    total_page_views: 36667,
    total_visitors: 17452,
    days: [ { date: "2026-08-19", page_views: 4955, visitors: 2246 } ]
  }.freeze

  test "returns the last 7 days of page views and visitors for garirbazar" do
    stub_report -> { REPORT } do
      get "/analytics/garirbazar"
    end

    assert_response :success
    body = response.parsed_body
    assert_equal 36667, body["total_page_views"]
    assert_equal 17452, body["total_visitors"]
    assert_equal "2026-08-19", body["start_date"]
    assert_equal "2026-08-25", body["end_date"]
    assert_equal [ { "date" => "2026-08-19", "page_views" => 4955, "visitors" => 2246 } ], body["days"]
  end

  test "returns 502 when Google Analytics is unreachable" do
    stub_report -> { raise GoogleAnalyticsService::Error, "boom" } do
      get "/analytics/garirbazar"
    end

    assert_response :bad_gateway
    assert_equal "Analytics data is unavailable right now", response.parsed_body["error"]
  end

  private

  # Replaces GoogleAnalyticsService.new for the block. Removing the singleton
  # method afterwards restores the inherited Class#new, since the service does
  # not define one of its own.
  def stub_report(result)
    service = Object.new
    service.define_singleton_method(:report) { |**| result.call }
    GoogleAnalyticsService.define_singleton_method(:new) { |**| service }

    yield
  ensure
    GoogleAnalyticsService.singleton_class.send(:remove_method, :new)
  end
end
