class Command::Parser::Context
  attr_reader :user, :url

  def initialize(user, url:)
    @user = user
    @url = url

    extract_url_components
  end

  def cards
    if viewing_card_contents?
      user.accessible_cards.where id: params[:id]
    elsif viewing_cards_index?
      filter.cards.published
    elsif viewing_search_results?
      user.accessible_cards.where(id: user.search(params[:q]).select(:card_id))
    else
      Card.none
    end
  end

  def viewing_card_contents?
    viewing_card_perma?
  end

  def viewing_list_of_cards?
    viewing_cards_index? || viewing_search_results?
  end

  def find_user(string)
    if string.starts_with?("gid://")
      User.find_by_id(GlobalID::Locator.locate(string).id)
    else
      string_without_at = string.delete_prefix("@")
      User.all.find { |user| user.mentionable_handles.include?(string_without_at.downcase) }
    end
  end

  def find_workflow_stage(string)
    candidate_stages.find do |stage|
      stage.name.downcase.include?(combined_arguments.downcase)
    end
  end

  def find_tag(string)
    Tag.find_by_title(string)
  end

  def find_collection(string)
    Collection.where("lower(name) like ?", "%#{name.downcase}%").first
  end

  private
    attr_reader :controller, :action, :params

    MAX_CARDS = 20
    MAX_CLOSED_CARDS = 10

    def filter
      user.filters.from_params(params.permit(*Filter::Params::PERMITTED_PARAMS).reverse_merge(**FilterScoped::DEFAULT_PARAMS))
    end

    def viewing_card_perma?
      controller == "cards" && action == "show"
    end

    def viewing_cards_index?
      controller == "cards" && action == "index"
    end

    def viewing_search_results?
      controller == "searches" && action == "show"
    end

    def extract_url_components
      uri = URI.parse(url || "")
      route = Rails.application.routes.recognize_path(uri.path)
      @controller = route[:controller]
      @action = route[:action]
      @params =  ActionController::Parameters.new(Rack::Utils.parse_nested_query(uri.query).merge(route.except(:controller, :action)))
    end

    def candidate_stages
      Workflow::Stage.where(workflow_id: cards.joins(:collection).select("collections.workflow_id").distinct)
    end
end
