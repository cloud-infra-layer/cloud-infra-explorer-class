class CostSnapshot < ApplicationRecord
  GRANULARITIES = %w[DAILY MONTHLY].freeze

  belongs_to :environment

  validates :period_start, :period_end, :granularity, :service_code, :amount, :currency, presence: true
  validates :granularity, inclusion: { in: GRANULARITIES }
  validates :currency, inclusion: { in: %w[USD] }
  validates :amount, numericality: true
  validates :service_code, uniqueness: {
    scope: %i[environment_id period_start period_end granularity]
  }
  validate :period_order

  private

  def period_order
    return if period_start.blank? || period_end.blank?
    errors.add(:period_end, "cannot be before period_start") if period_end < period_start
  end
end
