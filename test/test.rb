require 'application'
require 'test/unit'
require 'rack/test'

set :environment, :test

class LazarTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

	def setup
		@dataset = OpenTox::Dataset.create :name => "Hamster Carcinogenicity"
	 	@dataset.import :csv => File.join(File.dirname(__FILE__), "hamster_carcinogenicity.csv"), :compound_format => "smiles", :feature_type => "activity"
	end

	def teardown
		@dataset.delete
	end

	def test_algorithms
		get '/algorithms'
		assert last_response.body.include?("classification")
	end

	def test_create_model_and_predict
		post '/algorithm/classification', :dataset_uri => @dataset.uri
		assert last_response.ok?
		model_uri = last_response.body
		get model_uri
		assert last_response.ok?
		get '/models'
		assert last_response.body.include? model_uri
		query_structure = OpenTox::Compound.new :smiles => 'c1ccccc1NN'
		#query_structure = OpenTox::Compound.new :smiles => '[O-]C(C)=O.[O-]C(C)=O.[Pb+2].[OH-].[OH-].[Pb+2].[OH-].[OH-].[Pb+2]'
		post model_uri, :compound_uri => query_structure.uri
		assert last_response.ok?
		assert last_response.body.include? 'classification/true'
		puts last_response.body
	end

end
