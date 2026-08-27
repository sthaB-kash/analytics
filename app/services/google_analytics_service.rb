require "google/analytics/data/v1beta"

# Reads traffic counts from the Google Analytics Data API (GA4).
class GoogleAnalyticsService
  # Wraps every failure to reach or read from Google so callers only rescue one class.
  class Error < StandardError; end

  DEFAULT_DAYS = 7

  # Reported name => GA4 metric. "screenPageViews" is the GA4 successor to the old
  # pageviews metric; "activeUsers" is what the GA4 UI shows as Users.
  METRICS = {
    page_views: "screenPageViews",
    visitors: "activeUsers"
  }.freeze

  def initialize(property_id: nil, credentials: Rails.application.credentials.google_analytics)
    @credentials = credentials || {}
    @property_id = (property_id || @credentials[:property_id]).to_s

    raise Error, "No Google Analytics property_id configured" if @property_id.blank?
  end

  # Page views and visitors for the last `days` complete days, ending yesterday --
  # the same window the GA4 UI calls "Last 7 days". Today is excluded because it is
  # still accumulating and would report a partial count.
  #
  # The totals come from the API's own aggregation rather than a sum of the daily
  # rows. It matters for visitors: a person visiting on three days counts once in
  # the total but appears in three rows, so summing rows overcounts returning
  # visitors. Page views are additive, so there the total does equal the sum.
  def report(days: DEFAULT_DAYS)
    end_date = Date.current.yesterday
    start_date = end_date - (days - 1)

    response = run_report(start_date:, end_date:)
    by_date = daily_counts(response)

    {
      property_id: @property_id,
      start_date: start_date.to_s,
      end_date: end_date.to_s,
      **totals(response, by_date),
      # GA omits days with no traffic; fill them so the series always has one
      # entry per day and callers can chart it without patching holes.
      days: (start_date..end_date).map do |date|
        { date: date.to_s, **by_date.fetch(date, zero_counts) }
      end
    }
  end

  private

  def run_report(start_date:, end_date:)
    request = Google::Analytics::Data::V1beta::RunReportRequest.new(
      property: "properties/#{@property_id}",
      date_ranges: [ { start_date: start_date.to_s, end_date: end_date.to_s } ],
      dimensions: [ { name: "date" } ],
      metrics: METRICS.values.map { |metric| { name: metric } },
      metric_aggregations: [ :TOTAL ]
    )

    client.run_report(request)
  rescue Google::Cloud::Error => e
    raise Error, "Google Analytics request failed: #{e.message}"
  end

  def client
    Google::Analytics::Data::V1beta::AnalyticsData::Client.new do |config|
      config.credentials = {
        type: "service_account",
        client_email: @credentials[:client_email],
        private_key: private_key
      }
    end
  rescue Google::Cloud::Error, ArgumentError, OpenSSL::PKey::PKeyError => e
    raise Error, "Google Analytics credentials are invalid: #{e.message}"
  end

  # Service account keys are stored as a single line with literal "\n" escapes.
  # googleauth only unescapes those on its env-var path, not for an inline hash,
  # so OpenSSL would reject the key ("Neither PUB key nor PRIV key") without this.
  def private_key
    @credentials[:private_key].to_s.gsub('\n', "\n")
  end

  def daily_counts(response)
    response.rows.to_h do |row|
      [ Date.parse(row.dimension_values.first.value), counts_from(row) ]
    end
  rescue Date::Error => e
    raise Error, "Google Analytics returned an unreadable date: #{e.message}"
  end

  # Falls back to summing the daily rows if the aggregation row is missing, which
  # slightly overcounts visitors active on more than one day.
  def totals(response, by_date)
    total_row = response.totals.first
    counts = if total_row
      counts_from(total_row)
    else
      METRICS.keys.index_with { |name| by_date.values.sum { |day| day[name] } }
    end

    counts.transform_keys { |name| :"total_#{name}" }
  end

  # GA returns metric values positionally, in the order they were requested.
  def counts_from(row)
    METRICS.keys.zip(row.metric_values).to_h do |name, value|
      [ name, value.value.to_i ]
    end
  end

  def zero_counts
    METRICS.keys.index_with(0)
  end
end
