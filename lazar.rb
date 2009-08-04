#['rubygems', 'sinatra', 'rest_client', 'sinatra/url_for', 'crack/xml', 'dm-core', 'spork'].each do |lib|
['rubygems', 'sinatra', 'rest_client', 'sinatra/url_for', 'crack/xml', 'dm-core', 'builder', 'logger'].each do |lib|
	require lib
end

DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/lazar.sqlite3")

class Model
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	property :feature_dataset_uri, String
	property :training_dataset_uri, String
end

Model.auto_migrate! unless File.exists?("lazar.sqlite3")

COMPOUNDS_URI = 'http://webservices.in-silico.ch/compounds/'
FEATURES_URI  = 'http://webservices.in-silico.ch/features/'
DATASET_URI   = 'http://localhost:4567/'
FEATURE_GENERATION_URI = 'http://localhost:9394/'
@similarity_prediction = RestClient::Resource.new 'http://webservices.in-silico.ch/weighted_similarity_classification'

get '/?' do # get index of models
	Model.all.collect{ |m| url_for("/", :full) + m.id.to_s }.join("\n")
end

get '/:id' do
	@model = Model.get(params[:id])
	builder :model
end

get '/:id/:inchikey' do # show prediction
	@prediction = Prediction.first(:model_id => params[:id], :compound_uri => params[:compound_uri])
	builder :prediction
end

post '/:id' do # create prediction
	unless prediction = Prediction.first(:model_id => params[:id], :compound_uri => params[:compound_uri])
		Spork.spork do
			Prediction.create(@similarity_prediction.post, :compound_uri => params[:compound_uri], :feature_dataset_uri => Model.get(params[:id]).feature_dataset_uri)
		end
	end
	inchikey = @compounds.get "#{params[:compound_uri]}.inchikey"
	# or redirect?
	url_for("/#{params[:id]}/#{inchikey}", :full)
end

post '/' do # create model

	training_dataset_uri = RestClient.post DATASET_URI, :name => params[:name]
	dataset = RestClient::Resource.new training_dataset_uri
	model = Model.create(:name => params[:name], :training_dataset_uri => training_dataset_uri)

	#Spork.spork do
	pid = fork do
	
		# create model from a tab delimited file
		File.open(params[:file][:tempfile].path).each_line do |line|
			items = line.split(/\s+/)
			begin
				compound_uri = COMPOUNDS_URI + URI.encode(items[0])
				#compound_uri = RestClient.post COMPOUNDS_URI, :smiles => items[0]
			rescue
				puts "Failed to get InChI key for #{items[0]}"
			end
				feature_uri = RestClient.post FEATURES_URI, :name => params[:name], :value => items[1]
				dataset.put :compound_uri => compound_uri, :feature_uri => feature_uri
				model.training_dataset_uri = training_dataset_uri
				model.save
			#rescue
				#puts "Creation of feature #{params[:name]}:#{items[1]} for compound #{items[0]} failed."
			#end
		end


		feature_dataset_uri = RestClient.post FEATURE_GENERATION_URI, :dataset_uri => training_dataset_uri
		model.feature_dataset_uri = feature_dataset_uri.chomp 
		model.save

		# create features
		#feature_dataset_uri = @feature_generation.post :dataset_uri => params[:dataset_uri]
		#model = Model.create(:name => params[:name], :training_dataset_uri => training_dataset_uri, :feature_dataset_uri => feature_dataset_uri)
		#model.save
		# validate
		# or redirect?

	end

	Process.detach(pid)
	url_for("/", :full) + model.id.to_s 
end
