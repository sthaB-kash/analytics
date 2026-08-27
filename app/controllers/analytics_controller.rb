class AnalyticsController < ApplicationController
  # The Data API is rate limited and a report takes about a second, so serve
  # repeat callers from the cache. The window only advances once a day.
  CACHE_TTL = 15.minutes

  rescue_from GoogleAnalyticsService::Error, with: :upstream_unavailable

  # GET /analytics/garirbazar
  def garirbazar
    render json: report_for("garirbazar")
  end

  private

  def report_for(site)
    Rails.cache.fetch("analytics/#{site}/report/7d/#{Date.current}", expires_in: CACHE_TTL) do
      GoogleAnalyticsService.new.report
    end
  end

  def upstream_unavailable(error)
    Rails.logger.error("Google Analytics: #{error.message}")
    render json: { error: "Analytics data is unavailable right now" }, status: :bad_gateway
  end
end
