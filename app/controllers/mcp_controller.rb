require Rails.root.join("config/mcp")

class McpController < ApplicationController
  skip_forgery_protection

  def create
    body, status = dispatch_rpc_request
    render json: body, status: status
  end

  private
    TOOLS = Mcp.definition.tools

    def dispatch_rpc_request
      case rpc_method
      when "tools/list"
        [ rpc_success(result: { tools: TOOLS }), :ok ]
      when "tools/call"
        dispatch_tool_call
      else
        [ rpc_error(code: -32601, message: "Unknown method #{rpc_method.inspect}"), :bad_request ]
      end
    rescue ActiveRecord::RecordNotFound => error
      [ rpc_error(code: -32004, message: error.message), :not_found ]
    rescue ActionController::ParameterMissing => error
      [ rpc_error(code: -32602, message: error.message), :bad_request ]
    end

    def dispatch_tool_call
      if handler = tool_handlers[tool_name]
        handler.call(tool_arguments)
      else
        [ rpc_error(code: -32601, message: "Unknown tool #{tool_name.inspect}"), :bad_request ]
      end
    end

    def list_boards_tool(arguments)
      boards = Current.user.boards.alphabetically.includes(:columns)
      payload = { boards: boards.map { |board| board_payload(board) } }

      [ rpc_success(result: response_payload("Boards", payload)), :ok ]
    end

    def show_board_tool(arguments)
      board = Current.user.boards.find(arguments.require(:board_id))
      cards = board.cards.latest.preload(:column).limit(25)

      payload = { board: board_payload(board).merge(cards: cards.map { |card| card_payload(card) }) }

      [ rpc_success(result: response_payload("Board #{board.name}", payload)), :ok ]
    end

    def create_card_tool(arguments)
      board = Current.user.boards.find(arguments.require(:board_id))
      attributes = {
        title: arguments.require(:title),
        description: arguments[:description],
        status: "published",
        creator: Current.user
      }.compact

      card = board.cards.create!(attributes)

      [ rpc_success(result: response_payload("Card created", { card: card_payload(card) })), :created ]
    end

    def close_card_tool(arguments)
      card = Current.user.accessible_cards.find_by!(number: arguments.require(:card_number))
      card.close

      [ rpc_success(result: response_payload("Card closed", { card: card_payload(card) })), :ok ]
    end

    def create_comment_tool(arguments)
      card = Current.user.accessible_cards.find_by!(number: arguments.require(:card_number))
      comment = card.comments.create!(body: arguments.require(:body))

      payload = { comment: comment_payload(comment), card: card_payload(card) }

      [ rpc_success(result: response_payload("Comment created", payload)), :created ]
    end

    def rpc_method
      params[:method]
    end

    def rpc_id
      params[:id]
    end

    def rpc_params
      params[:params] || {}
    end

    def tool_name
      rpc_params[:name]
    end

    def tool_arguments
      if rpc_params[:arguments].is_a?(ActionController::Parameters)
        rpc_params[:arguments]
      else
        ActionController::Parameters.new(rpc_params[:arguments] || {})
      end
    end

    def tool_handlers
      {
        "list_boards" => method(:list_boards_tool),
        "show_board" => method(:show_board_tool),
        "create_card" => method(:create_card_tool),
        "close_card" => method(:close_card_tool),
        "create_comment" => method(:create_comment_tool)
      }
    end

    def board_payload(board)
      {
        id: board.id,
        name: board.name,
        path: board_path(board, format: :json),
        columns: board.columns.order(:position).map { |column| column_payload(column) }
      }
    end

    def column_payload(column)
      if column.present?
        { id: column.id, name: column.name, color: column.color }
      else
        nil
      end
    end

    def card_payload(card)
      {
        id: card.id,
        number: card.number,
        title: card.title,
        status: card.status,
        column: column_payload(card.column),
        path: card_path(card, format: :json),
        closed: card.closed?
      }
    end

    def comment_payload(comment)
      {
        id: comment.id,
        body: comment.body.to_plain_text,
        creator: comment.creator.name,
        created_at: comment.created_at
      }
    end

    def response_payload(title, data)
      text = "#{title}\n#{JSON.pretty_generate(data)}"

      { content: [ text_content(text) ], data: data }
    end

    def text_content(text)
      { type: "text", text: text }
    end

    def rpc_success(result:)
      { jsonrpc: "2.0", id: rpc_id, result: result }
    end

    def rpc_error(code:, message:)
      { jsonrpc: "2.0", id: rpc_id, error: { code: code, message: message } }
    end
end
