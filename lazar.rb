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
			feature_uri = lazar.dependent_variable + "_lazar_classification"
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
			feature_uri = lazar.dependent_variable
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
		owl = OpenTox::Owl.new 'Model', uri
		owl.source = "http://github.com/helma/opentox-model"
		#owl.algorithm = data.algorithm
		owl.dependentVariable = data.activity_dataset_uri
		owl.independentVariables = data.feature_dataset_uri
		owl.rdf
	end

end

get '/:id/?' do
	model = Lazar.get(params[:id])
	halt 404, "Model #{uri} not found." unless model
	accept = request.env['HTTP_ACCEPT']
	accept = "application/rdf+xml" if accept == '*/*' or accept =~ /html/ or accept == '' or accept.nil?
	case accept
	when "application/rdf+xml"
		response['Content-Type'] = 'application/rdf+xml'
		model.to_owl
	when /yaml/
		response['Content-Type'] = 'application/x-yaml'
		model.yaml
	else
		halt 400, "Unsupported MIME type '#{accept}'"
	end
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
	prediction.title = URI.decode YAML.load(lazar.yaml).dependent_variable.split(/#/).last

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

