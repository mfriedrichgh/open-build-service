RSpec.describe Role do
  let(:role) { create(:role) }

  describe 'validations' do
    it { is_expected.to validate_length_of(:title).is_at_least(2).with_message('must have more than two characters') }
    it { is_expected.to validate_length_of(:title).is_at_most(100).with_message('must have less than 100 characters') }
    it { expect(role).to validate_uniqueness_of(:title).with_message('is the name of an already existing role') }
  end

  describe '::hashed' do
    # created by db/seeds.rb
    let(:existing_role_titles) { ['Admin', 'maintainer', 'bugowner', 'reviewer', 'downloader', 'reader'] }

    it 'returns a hashed version of Role.all with role titles as key' do
      existing_role_titles.each do |title|
        expect(Role.hashed[title]).to eq(Role.where(title: title).first)
      end
    end
  end

  describe '::local_roles' do
    let(:expected_local_roles) { Role.where(title: ['maintainer', 'bugowner', 'reviewer', 'downloader', 'reader']) }

    it 'returns an array with all local role instances' do
      expect(Role.local_roles).to match_array(expected_local_roles)
    end
  end

  describe '::global_roles' do
    let(:expected_global_roles) { ['Admin'] }

    it 'returns an array with all global role titles' do
      expect(Role.global_roles).to match_array(expected_global_roles)
    end
  end

  describe '::find_by_title!' do
    context 'called for an existing record' do
      it 'returns the queried role' do
        expect(Role.find_by_title!(role.title)).to eq(role)
      end
    end

    context 'called for a non-existing record' do
      it 'raises an APIError' do
        expect { Role.find_by_title!('foobar') }.to raise_error(Role::NotFound, "Couldn't find Role 'foobar'")
      end
    end
  end

  describe '#to_param' do
    it { expect(role.to_param).to eq(role.title) }
  end

  describe '#to_s' do
    it { expect(role.to_s).to eq(role.title) }
  end
end
