class Command::ChatQuery < Command
  store_accessor :data, :query, :params

  def title
    "Chat query '#{query}'"
  end

  def execute
    response = chat.ask query
    Rails.logger.info "***\n#{response.content}\n***"
    response = replace_names_with_ids(JSON.parse(response.content))
    Command::Result::ChatResponse.new(JSON.pretty_generate(response))
  end

  private
    def chat
      chat = RubyLLM.chat
      chat.with_instructions(prompt)
    end

    def prompt
      <<~PROMPT
        You are a helpful assistant that translates natural language into commands that Fizzy understand.

        Fizzy supports the following commands:

        - Assign users to cards: /assign [user]
        - Close cards: /close [optional reason]
        - Tag cards: /tag [tag-name]
        - Search cards: /search. See how this works below:

        asks for a certain set of cards, you can use the /search command to filter. The /search command (and only this
        command) supports the following parameters:

          - assignment_status: can be "unassigned". Only include if asking for unassigned cards explicitly
          - indexed_by: can be "newest", "oldest", "latest", "stalled", "closed"
          - engagement_status: can be "considering" or "doing"
          - card_ids: a list of card ids
          - assignee_ids: a list of assignee names
          - creator_id: the name of a person
          - collection_ids: a list of collection names. Cards are contained in collections. Don't use unless mentioning
              specific collections.
          - tag_ids: a list of tag names.
          - terms: a list of terms to search for. Use this option to refine searches based on further keyword-based
             queries.

        The output will be in JSON. It will contain a list of commands. Each command will be a JSON object like:

        { command: "/close" }

        For the case of the /search command, it can also contain additional params:

        { command: "/search", indexed_by: "closed", collection_ids: [ "Writebook", "Design" ] }

        Notice that there are overlapping commands (filter by assignee or assign cards). Favor filtering/queries for
        commands like "cards assigned to someone".

        Notice that only /search commands carry additional JSON params. For /tag, /close and /assign just append the
        param to the string command. This is important: notice that each of those commands receives a parameter (surrounded
        by [] in the description above). Make sure if you invoke a given command you pass the params. Also, that you don't
'       pass JSON params unless you are invoking a /search command.

        For example, to assign a card, you invoke `assign kevin` instead of:

          {
            "command": "/assign",
            "assignee_ids": [
              "kevin"
            ]
          }

        Please combine commands to satisfy what the user needs. E.g: search with keywords and filters and then apply
        as many commands as needed. Make sure you don't leave actions mentioned in the query needs unattended.'

        Make sure to place into double quotes the strings in JSON values and that you generate valid JSON. I want a
        JSON list like [{}, {}...]
      PROMPT
    end

    def replace_names_with_ids(commands)
      commands.each do |command|
        if command["command"] == "/search"
          command["assignee_ids"] = command["assignee_ids"]&.filter_map { |name| assignee_from(name)&.id }
          command["creator_id"] = assignee_from(command["creator_id"])&.id if command["creator_id"]
          command["collection_ids"] = command["collection_ids"]&.filter_map { |name| Collection.where("lower(name) = ?", name.downcase).first&.id }
          command["tag_ids"] = command["tag_ids"]&.filter_map { |name| ::Tag.find_by_title(name)&.id }
          command.compact!
        end
      end
    end

    def assignee_from(string)
      string_without_at = string.delete_prefix("@")
      User.all.find { |user| user.mentionable_handles.include?(string_without_at) }
    end

end
