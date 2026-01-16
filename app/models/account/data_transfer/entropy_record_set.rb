class Account::DataTransfer::EntropyRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    auto_postpone_period
    container_id
    container_type
    created_at
    id
    updated_at
  ].freeze

  private
    def records
      Entropy.where(account: account)
    end

    def export_record(entropy)
      zip.add_file "data/entropies/#{entropy.id}.json", entropy.as_json.to_json
    end

    def files
      zip.glob("data/entropies/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Entropy.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Entropy record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end

      unless %w[Account Board].include?(data["container_type"])
        raise IntegrityError, "#{file_path} has invalid container_type: #{data['container_type']}"
      end
    end
end
