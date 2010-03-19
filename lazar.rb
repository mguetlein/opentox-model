class Lazar < Model

	attr_accessor :prediction_dataset

	def classify(compound_uri,prediction)

		prediction.title += " lazar classification"
    
		lazar = YAML.load self.yaml
		compound = OpenTox::Compound.new(:uri => compound_uri)
		compound_matches = compound.match lazar.features

		conf = 0.0
		similarities = {}
		classification = nil

		lazar.fingerprints.each do |uri,matches|

			sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(compound_matches,matches,lazar.p_values)
			if sim > 0.3
				similarities[uri] = sim
				lazar.activities[uri].each do |act|
					case act.to_s
					when 'true'
						conf += OpenTox::Utils.gauss(sim)
					when 'false'
						conf -= OpenTox::Utils.gauss(sim)
					end
				end
			end
		end
	
		conf = conf/similarities.size
		if conf > 0.0
			classification = true
		elsif conf < 0.0
			classification = false
		end

		if (classification != nil)
			feature_uri = lazar.dependent_variables + "_lazar_classification"
			prediction.compounds << compound_uri
			prediction.features << feature_uri 
			prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
			tuple = { 
					:classification => classification,
					:confidence => conf,
					:similarities => similarities,
					:features => compound_matches
			}
			prediction.data[compound_uri] << {feature_uri => tuple}
		end
    
	end

	def database_activity?(compound_uri,prediction)
		# find database activities
		lazar = YAML.load self.yaml
		db_activities = lazar.activities[compound_uri]
		if db_activities
			prediction.source = lazar.activity_dataset_uri
			feature_uri = lazar.dependent_variables
			prediction.compounds << compound_uri
			prediction.features << feature_uri
			prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
			db_activities.each do |act|
				prediction.data[compound_uri] << {feature_uri => act}
			end
			true
		else
			false
		end
	end

	def to_owl
		data = YAML.load(yaml)
		activity_dataset = YAML.load(RestClient.get(data.activity_dataset_uri, :accept => 'application/x-yaml').to_s)
		feature_dataset = YAML.load(RestClient.get(data.feature_dataset_uri, :accept => 'application/x-yaml').to_s)
		owl = OpenTox::Owl.create 'Model', uri
		owl.source = "http://github.com/helma/opentox-model"
		owl.title = "#{URI.decode(activity_dataset.title)} lazar classification"
		owl.date = created_at.to_s
		owl.algorithm = data.algorithm
		owl.dependentVariables = activity_dataset.features.join(', ')
		owl.independentVariables = feature_dataset.features.join(', ')
		owl.predictedVariables = activity_dataset.features.join(', ') + "_lazar_classification"
		owl.parameters = {
			"Dataset URI" =>
				{ :scope => "mandatory", :value => data.activity_dataset_uri },
			"Feature URI for dependent variable" =>
				{ :scope => "mandatory", :value =>  activity_dataset.features.join(', ')},
			"Feature generation URI" =>
				{ :scope => "mandatory", :value => feature_dataset.source }
		}
		owl.trainingDataset = data.activity_dataset_uri
		owl.rdf
	end

end

get '/:id/?' do
	accept = request.env['HTTP_ACCEPT']
	accept = "application/rdf+xml" if accept == '*/*' or accept == '' or accept.nil?
	# workaround for browser links
	case params[:id]
	when /.yaml$/
		params[:id].sub!(/.yaml$/,'')
		accept =  'application/x-yaml'
	when /.rdf$/
		params[:id].sub!(/.rdf$/,'')
		accept =  'application/rdf+xml'
	end
	model = Lazar.get(params[:id])
	halt 404, "Model #{params[:id]} not found." unless model
	case accept
	when "application/rdf+xml"
		response['Content-Type'] = 'application/rdf+xml'
		unless model.owl # lazy owl creation
			model.owl = model.to_owl
			model.save
		end
		model.owl
	when /yaml/
		response['Content-Type'] = 'application/x-yaml'
		model.yaml
	else
		halt 400, "Unsupported MIME type '#{accept}'"
	end
end

get '/:id/algorithm/?' do
	response['Content-Type'] = 'text/plain'
	YAML.load(Lazar.get(params[:id]).yaml).algorithm
end

get '/:id/training_dataset/?' do
	response['Content-Type'] = 'text/plain'
	YAML.load(Lazar.get(params[:id]).yaml).activity_dataset_uri
end

get '/:id/feature_dataset/?' do
	response['Content-Type'] = 'text/plain'
	YAML.load(Lazar.get(params[:id]).yaml).feature_dataset_uri
end

post '/?' do # create model
	halt 400, "MIME type \"#{request.content_type}\" not supported." unless request.content_type.match(/yaml/)
	model = Lazar.new
	model.save
	model.uri = url_for("/#{model.id}", :full)
	model.yaml =	request.env["rack.input"].read
	model.save
	model.uri
end

post '/:id/?' do # create prediction

	lazar = Lazar.get(params[:id])
	halt 404, "Model #{params[:id]} does not exist." unless lazar
	halt 404, "No compound_uri or dataset_uri parameter." unless compound_uri = params[:compound_uri] or dataset_uri = params[:dataset_uri]

	prediction = OpenTox::Dataset.new 
	prediction.source = lazar.uri
	prediction.title = URI.decode YAML.load(lazar.yaml).dependent_variables.split(/#/).last

	if compound_uri
		lazar.classify(compound_uri,prediction) unless lazar.database_activity?(compound_uri,prediction) 
		LOGGER.debug prediction.to_yaml
		case request.env['HTTP_ACCEPT']
		when /yaml/ 
			prediction.to_yaml
		when 'application/rdf+xml'
			prediction.to_owl
		else
			halt 404, "Content type #{request.env['HTTP_ACCEPT']} not available."
		end

	elsif dataset_uri
		task = OpenTox::Task.create
		pid = Spork.spork(:logger => LOGGER) do
			task.started
			input_dataset = OpenTox::Dataset.find(dataset_uri)
			input_dataset.compounds.each do |compound_uri|
				lazar.classify(compound_uri,prediction) unless lazar.database_activity?(compound_uri,prediction)
			end
			uri = prediction.save.chomp
			task.completed(uri)
		end
		task.pid = pid
		LOGGER.debug "Prediction task PID: " + pid.to_s
		#status 303
		response['Content-Type'] = 'text/uri-list'
		task.uri + "\n"
	end

end

