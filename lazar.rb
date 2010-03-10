class Lazar < Model

	attr_accessor :dataset, :predictions

	def classify(compound_uri)
  
    #unless @dataset
		  #@dataset = OpenTox::Dataset.new
		  @predictions = {}
    #end
		lazar = YAML.load self.yaml
		compound = OpenTox::Compound.new(:uri => compound_uri)
		compound_matches = compound.match lazar.features

		conf = 0.0
		similarities = {}
		classification = nil

		lazar.fingerprints.each do |uri,matches|

			sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(compound_matches,matches,lazar.p_values)
			LOGGER.debug sim
			if sim > 0#.3
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
		LOGGER.debug conf
		
		#compound = @dataset.compounds[compound_uri]
		#feature = @dataset.features[lazar.endpoint]

		if (classification != nil)
			#tuple = @dataset.create_tuple(feature,{ 'lazar#classification' => classification, 'lazar#confidence' => conf})
			#@dataset.add_tuple compound,tuple
			@predictions[compound_uri] = { lazar.dependent_variable => { :lazar_prediction => {
					:classification => classification,
					:confidence => conf,
					:similarities => similarities,
					:features => compound_matches
				} } }
		end
    
	end

	def database_activity?(compound_uri)
		# find database activities
		lazar = YAML.load self.yaml
		db_activities = lazar.activities[compound_uri]
		if db_activities
			@predictions = {:compound_uri => { lazar.dependent_variable => {:measured_activities => db_activities}}}
			true
		else
			false
		end
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

	if compound_uri
		lazar.classify(compound_uri) unless lazar.database_activity?(compound_uri) 
	elsif dataset_uri
		input_dataset = OpenTox::Dataset.find(dataset_uri)
		input_dataset.compounds.each do |compound_uri|
			lazar.classify(compound_uri) unless lazar.database_activity?(compound_uri)
		end
	end

	case request.env['HTTP_ACCEPT']
	when /yaml/ 
		lazar.predictions.to_yaml
	else
		if params[:compound_uri]
			lazar.dataset.rdf
		elsif params[:dataset_uri]
			lazar.dataset.save
		end
	end

end

