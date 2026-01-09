class Account::Import::IdMapper
  attr_reader :account, :old_account_id, :old_external_account_id, :old_account_slug

  def initialize(account, old_account_data)
    @account = account
    @old_account_id = old_account_data["id"]
    @old_external_account_id = old_account_data["external_account_id"]
    @old_account_slug = AccountSlug.encode(@old_external_account_id)
    @mappings = Hash.new { |h, k| h[k] = {} }
  end

  def map(type, old_id, new_id)
    @mappings[type][old_id] = new_id
  end

  def [](type)
    @mappings[type]
  end

  def mapped?(type, old_id)
    @mappings[type].key?(old_id)
  end

  def lookup(type, old_id)
    @mappings[type][old_id] || old_id
  end

  # Remap account_id and specified foreign keys in a data hash
  # foreign_keys is a Hash of { "field_name" => :type }
  def remap(data, foreign_keys: {})
    data = data.dup
    data["account_id"] = account.id if data.key?("account_id")

    foreign_keys.each do |field, type|
      old_id = data[field]
      next unless old_id
      next unless @mappings[type].key?(old_id)

      data[field] = @mappings[type][old_id]
    end

    data
  end

  # Common foreign key mappings for user-related fields
  USER_FOREIGN_KEYS = {
    "user_id" => :users,
    "creator_id" => :users,
    "assignee_id" => :users,
    "assigner_id" => :users,
    "closer_id" => :users,
    "mentioner_id" => :users,
    "mentionee_id" => :users,
    "reacter_id" => :users
  }.freeze

  def remap_with_users(data, additional_foreign_keys: {})
    remap(data, foreign_keys: USER_FOREIGN_KEYS.merge(additional_foreign_keys))
  end
end
