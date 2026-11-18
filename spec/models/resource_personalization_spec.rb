require "rails_helper"

RSpec.describe Resource, "personalization", type: :model do
  let(:environment) { Environment.create!(name: "Personalization examples", provider: "aws", region: "us-east-1") }

  def create_resource(identifier, **attributes)
    environment.resources.create!(
      { provider: "aws", service: "ec2", resource_id: identifier,
        name: "Example server", region: "us-east-1", metadata: {} }.merge(attributes)
    )
  end

  it "defaults new resources to visible and unpinned" do
    resource = create_resource("i-defaults").reload

    expect(resource.pinned).to be(false)
    expect(resource.hidden).to be(false)
  end

  it "persists pinning, hiding, restoring, and unpinning independently" do
    resource = create_resource("i-actions")
    resource.update!(pinned: true, hidden: true)
    expect(resource.reload).to be_pinned
    expect(resource).to be_hidden

    resource.update!(hidden: false)
    expect(resource.reload).not_to be_hidden
    expect(resource).to be_pinned

    resource.update!(pinned: false)
    expect(resource.reload).not_to be_pinned
  end

  it "separates visible and hidden inventory without deleting either" do
    visible = create_resource("i-visible")
    hidden = create_resource("i-hidden", hidden: true)

    expect(environment.resources.visible).to contain_exactly(visible)
    expect(environment.resources.hidden).to contain_exactly(hidden)
    expect(environment.resources.count).to eq(2)
  end

  it "orders pinned resources first, then names, then IDs, with visibility applied separately" do
    ordinary = create_resource("i-ordinary", name: "Aardvark")
    later_name = create_resource("i-zebra", name: "Zebra", pinned: true)
    first_tie = create_resource("i-first", name: "Alpha", pinned: true)
    second_tie = create_resource("i-second", name: "Alpha", pinned: true)
    create_resource("i-hidden", name: "A", pinned: true, hidden: true)

    expect(environment.resources.visible.pinned_first.to_a).to eq([ first_tie, second_tie, later_name, ordinary ])
  end

  %i[pinned hidden].each do |attribute|
    it "rejects null #{attribute} at both model and database levels" do
      resource = create_resource("i-null-#{attribute}")
      resource[attribute] = nil
      expect(resource).not_to be_valid
      expect(resource.errors[attribute]).to be_present

      expect do
        Resource.transaction(requires_new: true) { resource.update_columns(attribute => nil) }
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
