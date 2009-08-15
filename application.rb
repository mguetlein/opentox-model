load 'environment.rb'

get '/models/?' do # get index of models
	Model.all.collect{ |m| m.uri }.join("\n")
end

get '/model/:id' do
	halt 404, "Model #{params[:id]} not found." unless model = Model.get(params[:id])
	halt 202, "Model #{params[:id]} still under construction, please try again later." unless model.finished
#	builder do |xml|
#		xml.instruct!
		model.to_yaml
#	end
	#xml model
end

post '/models' do # create a model

	training_dataset = OpenTox::Dataset.new :uri => params[:dataset_uri]
	model = Model.create(:name => training_dataset.name, :training_dataset_uri => training_dataset.uri)
	model.update_attributes(:uri => url_for("/model/", :full) + model.id.to_s)

	Spork.spork do
		feature_generation = OpenTox::Fminer.new(training_dataset)
		feature_dataset = feature_generation.dataset
		model.feature_dataset_uri = feature_dataset.uri.chomp 
		model.finished = true
		model.save
	end
	
	model.uri.to_s
end

delete '/model/:id' do
	halt 404, "Model #{params[:id]} not found." unless model = Model.get(params[:id])
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

	halt 404, "Model #{params[:id]} not found." unless model = Model.get(params[:id])
	query_compound = OpenTox::Compound.new :uri => params[:compound_uri]
	activity_dataset = OpenTox::Dataset.new :uri => model.training_dataset_uri

#	database_activities = activity_dataset.features(query_compound)

#	if database_activities.size > 0 # return database values
#		database_activities.collect{ |f| f.uri }.join('\n')

#	else # make prediction
		prediction = Prediction.find_or_create(:model_uri => model.uri, :compound_uri => params[:compound_uri])

		unless prediction.finished # present cached prediction if finished

			#Spork.spork do
				prediction.update_attributes(:uri => url_for("/prediction/", :full) + prediction.id.to_s)
				feature_dataset = OpenTox::Dataset.new :uri => model.feature_dataset_uri
				compound_descriptors = feature_dataset.all_compounds_and_features
				training_features = feature_dataset.all_features
				compound_activities = activity_dataset.all_compounds_and_features	# TODO: returns nil/fix in gem
				query_features = query_compound.match(training_features)
				query_features.each do |f|
					Feature.find_or_create(:feature_uri => f.uri, :prediction_uri => prediction.uri)
				end

				conf = 0.0

				compound_descriptors.each do |compound_uri,features|
					sim = similarity(features,query_features,model)
					if sim > 0.0
						puts sim
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

			#end
			
		end
		
		prediction.uri
#	end
end

# PREDICTIONS
get '/predictions?' do # get index of predictions
	Prediction.all.collect{ |p| p.uri }.join("\n")
end

get '/prediction/:id' do	# display prediction
	halt 404, "Prediction #{params[:id]} not found." unless prediction = Prediction.get(params[:id])
	#halt 202, "Prediction #{params[:id]} not yet finished, please try again later." unless prediction.finished
	halt 202, prediction.to_yaml unless prediction.finished
	prediction.to_yaml
	#xml prediction
end

get '/prediction/:id/neighbors' do	
	halt 404, "Prediction #{params[:id]} not found." unless prediction = Prediction.get(params[:id])
	halt 202, "Prediction #{params[:id]} not yet finished, please try again later." unless prediction.finished
	#xml Neighbor.all(:prediction_uri => prediction.uri)
	Neighbor.all(:prediction_uri => prediction.uri).to_yaml
end

get '/prediction/:id/features' do	
	halt 404, "Prediction #{params[:id]} not found." unless prediction = Prediction.get(params[:id])
	halt 202, "Prediction #{params[:id]} not yet finished, please try again later." unless prediction.finished
	#xml Feature.all(:prediction_uri => prediction.uri)
	Feature.all(:prediction_uri => prediction.uri).to_yaml
end

delete '/prediction/:id' do
	halt 404, "Prediction #{params[:id]} not found." unless prediction = Prediction.get(params[:id])
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
