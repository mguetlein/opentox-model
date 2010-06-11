class Lazar < Model

	attr_accessor :prediction_dataset

	# AM begin
	# regression function, created 06/10
	# ch: please properly integrate this into the workflow. You will need some criterium for distinguishing regression/classification (hardcoded regression for testing)
	def regrify(compound_uri,prediction)
    
		lazar = YAML.load self.yaml
		compound = OpenTox::Compound.new(:uri => compound_uri)

		# obtain X values for query compound
		compound_matches = compound.match lazar.features

		conf = 0.0
		similarities = {}
		regression = nil

		regr_occurrences = [] # occurrence vector with {0,1} entries
		sims = [] # similarity values between query and neighbors
		acts = [] # activities of neighbors for supervised learning
		neighbor_matches = [] # as in classification: URIs of matches
		gram_matrix = [] # square matrix of similarities between neighbors; implements weighted tanimoto kernel
		i = 0

		# aquire data related to query structure
		lazar.fingerprints.each do |uri,matches|
			sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(compound_matches,matches,lazar.p_values)
			lazar.activities[uri].each do |act|
				if sim > 0.3
					similarities[uri] = sim
					conf += OpenTox::Utils.gauss(sim)
					sims << OpenTox::Utils.gauss(sim)
					acts << Math.log10(act.to_f)
					neighbor_matches[i] = matches
					i+=1
				end
			end
		end
		conf = conf/similarities.size
		LOGGER.debug "Regression: found " + neighbor_matches.size.to_s + " neighbors."


		unless neighbor_matches.length == 0
			# gram matrix
			(0..(neighbor_matches.length-1)).each do |i|
				gram_matrix[i] = []
				# lower triangle
				(0..(i-1)).each do |j|
					sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(neighbor_matches[i], neighbor_matches[j], lazar.p_values)
					gram_matrix[i] << OpenTox::Utils.gauss(sim)
				end
				# diagonal element
				gram_matrix[i][i] = 1.0
				# upper triangle
				((i+1)..(neighbor_matches.length-1)).each do |j|
					sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(neighbor_matches[i], neighbor_matches[j], lazar.p_values)
					gram_matrix[i] << OpenTox::Utils.gauss(sim)
				end
			end


			# R integration
			require ("rinruby") # this requires R to be built with X11 support (implies package xorg-dev)
			R.eval "library('kernlab')" # this requires R package "kernlab" to be installed

			# set data
			R.gram_matrix = gram_matrix.flatten
			R.n = neighbor_matches.length
			R.y = acts
			R.sims = sims

			# prepare data
			R.eval "y<-as.vector(y)"
			R.eval "gram_matrix<-as.kernelMatrix(matrix(gram_matrix,n,n))"
			R.eval "sims<-as.vector(sims)"
			
			# model + support vectors
			R.eval "model<-ksvm(gram_matrix, y, kernel=matrix, type=\"nu-svr\", nu=0.8)"
			R.eval "sv<-as.vector(SVindex(model))"
			R.eval "sims<-sims[sv]"
			R.eval "sims<-as.kernelMatrix(matrix(sims,1))"
			R.eval "p<-predict(model,sims)[1,1]"
			regression = 10**(R.p.to_f)
			puts "Prediction is: '" + regression.to_s + "'."

		end

		if (regression != nil)
			feature_uri = lazar.dependentVariables
			prediction.compounds << compound_uri
			prediction.features << feature_uri 
			prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
			tuple = { 
					:classification => regression,
					:confidence => conf,
					:similarities => similarities,
					:features => compound_matches
					# uncomment to enable owl-dl serialisation of predictions
					# url_for("/lazar#classification") => classification,
					# url_for("/lazar#confidence") => conf,
					# url_for("/lazar#similarities") => similarities,
					# url_for("/lazar#features") => compound_matches
			}
			prediction.data[compound_uri] << {feature_uri => tuple}
		end


	end
	# AM end


	def classify(compound_uri,prediction)
    
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
					# uncomment to enable owl-dl serialisation of predictions
					# url_for("/lazar#classification") => classification,
					# url_for("/lazar#confidence") => conf,
					# url_for("/lazar#similarities") => similarities,
					# url_for("/lazar#features") => compound_matches
			}
			prediction.data[compound_uri] << {feature_uri => tuple}
		end
    
	end

	def database_activity?(compound_uri,prediction)
		# find database activities
		lazar = YAML.load self.yaml
		db_activities = lazar.activities[compound_uri]
		if db_activities
			prediction.creator = lazar.trainingDataset
			feature_uri = lazar.dependentVariables
			prediction.compounds << compound_uri
			prediction.features << feature_uri
			prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
			db_activities.each do |act|
				prediction.data[compound_uri] << {feature_uri => act}
        #tuple = { 
        #  :classification => act}
          #:confidence => "experimental"}
				#prediction.data[compound_uri] << {feature_uri => tuple}
			end
			true
		else
			false
		end
	end

	def to_owl
		data = YAML.load(yaml)
		activity_dataset = YAML.load(RestClient.get(data.trainingDataset, :accept => 'application/x-yaml').body)
		feature_dataset = YAML.load(RestClient.get(data.feature_dataset_uri, :accept => 'application/x-yaml').body)
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

get '/:id/trainingDataset/?' do
	response['Content-Type'] = 'text/plain'
	YAML.load(Lazar.get(params[:id]).yaml).trainingDataset
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
	prediction.title += " lazar classification"

	if compound_uri
		# AM: switch here between regression and classification
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
				# AM: switch here between regression and classification
				lazar.classify(compound_uri,prediction) unless lazar.database_activity?(compound_uri,prediction)
			end
			begin
				uri = prediction.save.chomp
			rescue
				halt 500, "Could not save prediction dataset"
			end
	  end
    halt 202,task_uri
	end

end

