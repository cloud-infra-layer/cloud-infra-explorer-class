class Scan < ApplicationRecord
  STATUSES = %w[running completed partial failed].freeze
  RESOURCE_TYPES = %w[ec2 s3].freeze
  ERROR_FIELDS = %w[resource_type code message].freeze

  belongs_to :environment

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validates :discovered_count, :created_count, :updated_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :resource_types_are_supported
  validate :error_details_are_structured
  validate :completion_time_matches_status

  private

  def resource_types_are_supported
    unless resource_types.is_a?(Array) && resource_types.any? &&
        resource_types.uniq == resource_types && resource_types.all? { |type| RESOURCE_TYPES.include?(type) }
      errors.add(:resource_types, "must be a nonempty array of unique ec2 or s3 strings")
    end
  end

  def error_details_are_structured
    valid_details = error_details.is_a?(Array) && error_details.all? do |detail|
      detail.is_a?(Hash) && detail.keys.sort == ERROR_FIELDS.sort &&
        detail.values.all? { |value| value.is_a?(String) && value.present? }
    end
    errors.add(:error_details, "must contain only resource_type, code, and message strings") unless valid_details
  end

  def completion_time_matches_status
    if status == "running"
      errors.add(:completed_at, "must be blank while running") if completed_at.present?
    elsif STATUSES.include?(status) && completed_at.blank?
      errors.add(:completed_at, "must be present when finished")
    end

    if started_at && completed_at && completed_at < started_at
      errors.add(:completed_at, "cannot be before started_at")
    end
  end
end
