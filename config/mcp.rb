module Mcp
  class Definition
    attr_reader :tools

    def initialize(tools)
      @tools = tools.freeze
    end
  end

  class Mapper
    attr_reader :tools

    def initialize
      @tools = []
    end

    def tool(name, description:, input_schema:)
      tools << {
        name: name.to_s,
        description: description,
        input_schema: input_schema
      }
    end
  end

  def self.draw(&block)
    mapper = Mapper.new
    mapper.instance_eval(&block)
    @definition = Definition.new(mapper.tools)
  end

  def self.definition
    @definition
  end
end

Mcp.draw do
  tool :list_boards,
    description: "List boards accessible to the authenticated user.",
    input_schema: { type: "object", properties: {} }

  tool :show_board,
    description: "Show board details, recent cards, and columns.",
    input_schema: {
      type: "object",
      properties: {
        board_id: { type: "string", description: "Board UUID" }
      },
      required: [ "board_id" ]
    }

  tool :create_card,
    description: "Create a published card on a board.",
    input_schema: {
      type: "object",
      properties: {
        board_id: { type: "string", description: "Board UUID" },
        title: { type: "string", description: "Card title" },
        description: { type: "string", description: "Optional rich text body" }
      },
      required: [ "board_id", "title" ]
    }

  tool :close_card,
    description: "Close a card by its account-wide number.",
    input_schema: {
      type: "object",
      properties: {
        card_number: { type: "integer", description: "Card number" }
      },
      required: [ "card_number" ]
    }

  tool :create_comment,
    description: "Create a comment on a card.",
    input_schema: {
      type: "object",
      properties: {
        card_number: { type: "integer", description: "Card number" },
        body: { type: "string", description: "Comment body" }
      },
      required: [ "card_number", "body" ]
    }
end
