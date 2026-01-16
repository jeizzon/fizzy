class Account::DataTransfer::AssignmentRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    assignee_id
    assigner_id
    card_id
    created_at
    id
    updated_at
  ].freeze

  private
    def records
      Assignment.where(account: account)
    end

    def export_record(assignment)
      zip.add_file "data/assignments/#{assignment.id}.json", assignment.as_json.to_json
    end

    def files
      zip.glob("data/assignments/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Assignment.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Assignment record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
