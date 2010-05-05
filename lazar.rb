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
			feature_uri = lazar.dependentVariables
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
			prediction.source = lazar.trainingDataset
			feature_uri = lazar.dependentVariables
			prediction.compounds << compound_uri
			prediction.features << feature_uri
			prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
			db_activities.each do |act|
        tuple = { 
          :classification => act,
          :confidence => 1}
				prediction.data[compound_uri] << {feature_uri => tuple}
			end
			true
		else
			false
		end
	end

	def to_owl
		data = YAML.load(yaml)
		activity_dataset = YAML.load(RestClient.get(data.trainingDataset, :accept => 'text/x-yaml').to_s)
		feature_dataset = YAML.load(RestClient.get(data.feature_dataset_uri, :accept => 'text/x-yaml').to_s)
		owl = OpenTox::Owl.create 'Model', uri
    owl.set("creator","http://github.com/helma/opentox-model")
    owl.set("title","#{URI.decode(activity_dataset.title)} lazar classification")
    owl.set("date",created_at.to_s)
    owl.set("algorithm",data.algorithm)
    owl.set("dependentVariables",activity_dataset.features.join(', '))
    owl.set("independentVariables",feature_dataset.features.join(', '))
    owl.set("predictedVariables",activity_dataset.features.join(', ') + "_lazar_classification")
    owl.set("trainingDataset",data.trainingDataset)
		owl.parameters = {
			"Dataset URI" =>
				{ :scope => "mandatory", :value => data.trainingDataset },
			"Feature URI for dependent variable" =>
				{ :scope => "mandatory", :value =>  activity_dataset.features.join(', ')},
			"Feature generation URI" =>
				{ :scope => "mandatory", :value => feature_dataset.creator }
		}
		
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
		accept =  'text/x-yaml'
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
		response['Content-Type'] = 'text/x-yaml'
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
	prediction.creator = lazar.uri
	prediction.title = URI.decode YAML.load(lazar.yaml).dependentVariables.split(/#/).last

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
    response['Content-Type'] = 'text/uri-list'
		task_uri = OpenTox::Task.as_task do
			input_dataset = OpenTox::Dataset.find(dataset_uri)
			input_dataset.compounds.each do |compound_uri|
				lazar.classify(compound_uri,prediction) unless lazar.database_activity?(compound_uri,prediction)
			end
			uri = prediction.save.chomp
	  end
    halt 202,task_uri
	end

end

