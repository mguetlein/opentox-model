load 'environment.rb'

# MODELS
get '/models?' do # get index of models
	Model.all.collect{ |m| m.uri }.join("\n")
end

get '/model/:id' do
	begin
		model = Model.get(params[:id])
	rescue
		status 404
		"Model #{params[:id]} not found"
	end
	if model.finished
		xml model
	else
		status 202
		"Model #{params[:id]} under construction"
	end
end

post '/models' do # create a model

	if params[:dataset_uri]
		training_dataset = OpenTox::Dataset.new :uri => params[:dataset_uri]
	else
		training_dataset = OpenTox::Dataset.new :name => params[:name]
	end
	model = Model.create(:name => params[:name], :training_dataset_uri => training_dataset.uri)
	model.update_attributes(:uri => url_for("/model/", :full) + model.id.to_s)

	pid = fork do #Spork.spork do
		unless params[:dataset_uri] # create model from a tab delimited file
			File.open(params[:file][:tempfile].path).each_line do |line|
				items = line.chomp.split(/\s+/)
				compound = OpenTox::Compound.new :smiles => items[0]
				feature = OpenTox::Feature.new :name => params[:name], :values => { 'classification' => items[1] }
				training_dataset.add(compound, feature)
			end
		end

		feature_generation = OpenTox::Fminer.new(training_dataset)
		feature_dataset = feature_generation.dataset
		model.feature_dataset_uri = feature_dataset.uri.chomp 
		model.finished = true
		model.save
	end
	Process.detach(pid)
	model.uri.to_s
end

delete '/model/:id' do
	begin
		model = Model.get params[:id]
	rescue
		status 404
		"Model #{params[:id]} not found"
	end
	model.predictions.each do |p|
		p.neighbors.each { |n| n.destroy }
		p.features.each { |n| f.destroy }
		p.destroy
	end
	model.destroy
	"Model #{params[:id]} succesfully deleted."
	# TODO: what happens with datasets, avoid stale datasets, but other components might need them
end

post '/model/:id' do # create prediction

	begin
		model = Model.get params[:id]
	rescue
		status 404
		"Model #{params[:id]} not found"
	end
	query_compound = OpenTox::Compound.new :uri => params[:compound_uri]
	activity_dataset = OpenTox::Dataset.new :uri => model.training_dataset_uri

	database_activities = activity_dataset.features(query_compound)

	if database_activities.size > 0 # return database values
		database_activities.collect{ |f| f.uri }.join('\n')

	else # make prediction
		prediction = Prediction.find_or_create(:model_uri => model.uri, :compound_uri => params[:compound_uri])

		unless prediction.finished # present cached prediction if finished

			#Spork.spork do
			pid = fork do
				prediction.update_attributes(:uri => url_for("/prediction/", :full) + prediction.id.to_s)
				feature_dataset = OpenTox::Dataset.new :uri => model.feature_dataset_uri
				compound_descriptors = feature_dataset.all_compounds_and_features
				training_features = feature_dataset.all_features
				compound_activities = activity_dataset.all_compounds_and_features
				query_features = query_compound.match(training_features)
				query_features.each do |f|
					puts f.uri
					Feature.find_or_create(:feature_uri => f.uri, :prediction_uri => prediction.uri)
				end

				conf = 0.0

				compound_descriptors.each do |compound_uri,features|
					sim = similarity(features,query_features,model)
					if sim > 0.0
						Neighbor.find_or_create(:compound_uri => compound_uri, :similarity => sim, :prediction_uri => prediction.uri)
						compound_activities[compound_uri].each do |a|
							case a.value('classification').to_s
							when 'true'
								conf += sim #TODO gaussian
							when 'false'
								conf -= sim #TODO gaussian
							end
						end
					end
				end

				if conf > 0.0
					classification = true
				elsif conf < 0.0
					classification = false
				end
				prediction.update_attributes(:confidence => conf, :classification => classification, :finished => true)
				prediction.save!
				puts prediction.to_yaml

			end
			Process.detach(pid)
		end
		
		prediction.uri
	end
end

# PREDICTIONS
get '/predictions?' do # get index of predictions
	Prediction.all.collect{ |p| p.uri }.join("\n")
end

get '/prediction/:id' do	# display prediction
	begin
		prediction = Prediction.get(params[:id])
	rescue
		status 404
		"Prediction #{params[:id]} not found."
	end
	if prediction.finished
		xml prediction
	else
		status 202
		"Prediction #{params[:id]} not yet finished."
	end
end

get '/prediction/:id/neighbors' do	
	begin
		prediction = Prediction.get(params[:id])
	rescue
		status 404
		"Prediction #{params[:id]} not found."
	end
	xml Neighbor.all(:prediction_uri => prediction.uri)
end

get '/prediction/:id/features' do	
	begin
		prediction = Prediction.get(params[:id])
	rescue
		status 404
		"Prediction #{params[:id]} not found."
	end
	xml Feature.all(:prediction_uri => prediction.uri)
end

delete '/prediction/:id' do
	begin
		p = Prediction.get(params[:id])
	rescue
		status 404
		"Prediction #{params[:id]} not found."
	end
	p.neighbors.each { |n| n.destroy }
	p.features.each { |f| f.destroy }
	p.destroy
	"Prediction #{params[:id]} succesfully deleted."
end

# Utility functions
def similarity(neighbor_features, query_features, model)

	nf = neighbor_features.collect{|f| f.uri }
	qf = query_features.collect{|f| f.uri }
	#common_features = neighbor_features & query_features
	#all_features    = neighbor_features | query_features
	common_features = nf & qf
	all_features    = nf | qf

	sum_p_common = 0.0
	sum_p_all = 0.0

	#all_features.each { |f| sum_p_all += f.value.to_f }
	#common_features.each { |f| sum_p_common += f.value.to_f }
	#sum_p_common/sum_p_all
	common_features.size.to_f/all_features.size.to_f

end

def xml(object)
	builder do |xml|
		xml.instruct!
		object.to_xml
	end
end
