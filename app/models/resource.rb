class Resource < ApplicationRecord
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

  validates :pinned, :hidden, inclusion: { in: [ true, false ] }

  validates :provider, :resource_id, :service, :name, presence: true
  validates :provider, inclusion: { in: %w[aws] }
  validates :service, inclusion: { in: %w[ec2 s3] }
  validates :resource_id,
    uniqueness: { scope: %i[environment_id provider service region] },
    if: -> { service == "ec2" }
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
