class Environment < ApplicationRecord
  has_many :resources, dependent: :restrict_with_error

  validates :name, :provider, :region, presence: true
  validates :provider, inclusion: { in: %w[aws] }
end
