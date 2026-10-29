class HomeController < ApplicationController
  def index
    @resource_counts = Resource.where(provider: "aws").group(:service).count
  end
end
