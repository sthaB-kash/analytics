class ApplicationController < ActionController::API
  def home
    render json: {
      status: :ok,
      message: "Google Analytics Service"
    }
  end
end
