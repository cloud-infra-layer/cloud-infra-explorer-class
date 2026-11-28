class Resource < ApplicationRecord
  SERVICES = %w[ec2 s3 rds bedrock].freeze
  REGION_SCOPED_SERVICES = %w[ec2 rds bedrock].freeze

  # Generic product categories map 1..n cloud services. Add services here instead of
  # hardcoding new top-nav links or dashboard cards.
  CATEGORIES = {
    "compute" => {
      label: "Compute",
      description: "Virtual machines and instance capacity.",
      services: %w[ec2]
    },
    "storage" => {
      label: "Storage",
      description: "Object storage buckets and data assets.",
      services: %w[s3]
    },
    "databases" => {
      label: "Database",
      description: "Managed database instances and clusters.",
      services: %w[rds]
    },
    "ai" => {
      label: "AI / ML",
      description: "Foundation models and generative AI services.",
      services: %w[bedrock]
    }
  }.freeze

  belongs_to :environment

  scope :visible, -> { where(hidden: false) }
  scope :hidden, -> { where(hidden: true) }
  scope :pinned_first, -> { order(pinned: :desc, name: :asc, id: :asc) }

  def self.search(query)
    term = query.to_s.strip
    return all if term.empty?

    pattern = "%#{sanitize_sql_like(term)}%"
    where("resources.name ILIKE :pattern OR resources.service ILIKE :pattern OR resources.resource_id ILIKE :pattern", pattern: pattern)
  end

  def self.services_for_category(category)
    CATEGORIES.dig(category.to_s, :services)
  end

  def self.category_for_service(service)
    CATEGORIES.each do |key, config|
      return key if config.fetch(:services).include?(service.to_s)
    end
    nil
  end

  validates :pinned, :hidden, inclusion: { in: [ true, false ] }

  validates :provider, :resource_id, :service, :name, presence: true
  validates :provider, inclusion: { in: %w[aws] }
  validates :service, inclusion: { in: SERVICES }
  validates :resource_id,
    uniqueness: { scope: %i[environment_id provider service region] },
    if: -> { REGION_SCOPED_SERVICES.include?(service) }
  validates :resource_id,
    uniqueness: { scope: %i[environment_id provider service] },
    if: -> { service == "s3" }

  validate :provider_matches_environment
  validate :metadata_is_a_hash

  private

  def provider_matches_environment
    if environment && provider != environment.provider
      errors.add(:provider, "must match the environment's provider")
    end
  end

  def metadata_is_a_hash
    errors.add(:metadata, "must be an object") unless metadata.is_a?(Hash)
  end
end
