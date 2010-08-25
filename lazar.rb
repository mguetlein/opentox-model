# R integration
# workaround to initialize R non-interactively (former rinruby versions did this by default)
# avoids compiling R with X
R = nil
require "rinruby" 
require "haml" 

class Lazar < Model

	attr_accessor :prediction_dataset

	# AM begin
	# regression function, created 06/10
	# ch: please properly integrate this into the workflow. You will need some criterium for distinguishing regression/classification (hardcoded regression for testing)
	def regression(compound_uri,prediction,verbose=false)
    
		lazar = YAML.load self.yaml
		compound = OpenTox::Compound.new(:uri => compound_uri)

		# obtain X values for query compound
		compound_matches = compound.match lazar.features

		conf = 0.0
		features = { :activating => [], :deactivating => [] }
		neighbors = {}
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
          neighbors[uri] = {:similarity => sim}
          neighbors[uri][:features] = { :activating => [], :deactivating => [] } unless neighbors[uri][:features]
          matches.each do |m|
            if lazar.effects[m] == 'activating'
              neighbors[uri][:features][:activating] << {:smarts => m, :p_value => lazar.p_values[m]}
            elsif lazar.effects[m] == 'deactivating'
              neighbors[uri][:features][:deactivating] << {:smarts => m, :p_value => lazar.p_values[m]}
            end
          end
          lazar.activities[uri].each do |act|
            neighbors[uri][:activities] = [] unless neighbors[uri][:activities]
            neighbors[uri][:activities] << act
          end
					conf += OpenTox::Utils.gauss(sim)
					sims << OpenTox::Utils.gauss(sim)
					#TODO check for 0 s
					acts << Math.log10(act.to_f)
					neighbor_matches[i] = matches
					i+=1
				end
			end
		end
		conf = conf/neighbors.size
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

			@r = RinRuby.new(false,false) # global R instance leads to Socket errors after a large number of requests
			@r.eval "library('kernlab')" # this requires R package "kernlab" to be installed
			LOGGER.debug "Setting R data ..."
			# set data
			@r.gram_matrix = gram_matrix.flatten
			@r.n = neighbor_matches.length
			@r.y = acts
			@r.sims = sims

			LOGGER.debug "Preparing R data ..."
			# prepare data
			@r.eval "y<-as.vector(y)"
			@r.eval "gram_matrix<-as.kernelMatrix(matrix(gram_matrix,n,n))"
			@r.eval "sims<-as.vector(sims)"
			
			# model + support vectors
			LOGGER.debug "Creating SVM model ..."
			@r.eval "model<-ksvm(gram_matrix, y, kernel=matrix, type=\"nu-svr\", nu=0.8)"
			@r.eval "sv<-as.vector(SVindex(model))"
			@r.eval "sims<-sims[sv]"
			@r.eval "sims<-as.kernelMatrix(matrix(sims,1))"
			LOGGER.debug "Predicting ..."
			@r.eval "p<-predict(model,sims)[1,1]"
			regression = 10**(@r.p.to_f)
			LOGGER.debug "Prediction is: '" + regression.to_s + "'."
			@r.quit # free R

		end

		if (regression != nil)
			feature_uri = lazar.dependentVariables
			prediction.compounds << compound_uri
			prediction.features << feature_uri 
			prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
			compound_matches.each { |m| features[lazar.effects[m].to_sym] << {:smarts => m, :p_value => lazar.p_values[m] } }
			tuple = { 
					File.join(@@config[:services]["opentox-model"],"lazar#regression") => regression,
					File.join(@@config[:services]["opentox-model"],"lazar#confidence") => conf
			}
      if verbose
        tuple[File.join(@@config[:services]["opentox-model"],"lazar#neighbors")] = neighbors
        tuple[File.join(@@config[:services]["opentox-model"],"lazar#features")] = features
      end
			prediction.data[compound_uri] << {feature_uri => tuple}
		end

	end
	# AM end


	def classification(compound_uri,prediction,verbose=false)
    
		lazar = YAML.load self.yaml
		compound = OpenTox::Compound.new(:uri => compound_uri)
		compound_matches = compound.match lazar.features

		conf = 0.0
		features = { :activating => [], :deactivating => [] }
		neighbors = {}
		classification = nil

		lazar.fingerprints.each do |uri,matches|

			sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(compound_matches,matches,lazar.p_values)
			if sim > 0.3
				neighbors[uri] = {:similarity => sim}
				neighbors[uri][:features] = { :activating => [], :deactivating => [] } unless neighbors[uri][:features]
				matches.each do |m|
					if lazar.effects[m] == 'activating'
						neighbors[uri][:features][:activating] << {:smarts => m, :p_value => lazar.p_values[m]}
					elsif lazar.effects[m] == 'deactivating'
						neighbors[uri][:features][:deactivating] << {:smarts => m, :p_value => lazar.p_values[m]}
					end
				end
				lazar.activities[uri].each do |act|
					neighbors[uri][:activities] = [] unless neighbors[uri][:activities]
					neighbors[uri][:activities] << act
					case act.to_s
					when 'true'
						conf += OpenTox::Utils.gauss(sim)
					when 'false'
						conf -= OpenTox::Utils.gauss(sim)
					end
				end
			end
		end
	
		conf = conf/neighbors.size
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
			compound_matches.each { |m| features[lazar.effects[m].to_sym] << {:smarts => m, :p_value => lazar.p_values[m] } }
			tuple = { 
        File.join(@@config[:services]["opentox-model"],"lazar#classification") => classification,
        File.join(@@config[:services]["opentox-model"],"lazar#confidence") => conf
			}
      if verbose
        tuple[File.join(@@config[:services]["opentox-model"],"lazar#neighbors")] = neighbors
        tuple[File.join(@@config[:services]["opentox-model"],"lazar#features")] = features
      end
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
			end
			true
		else
			false
		end
	end

	def to_owl
		data = YAML.load(yaml)
		activity_dataset = YAML.load(RestClient.get(data.trainingDataset, :accept => 'application/x-yaml').to_s)
		feature_dataset = YAML.load(RestClient.get(data.feature_dataset_uri, :accept => 'application/x-yaml').to_s)
		owl = OpenTox::Owl.create 'Model', uri
    owl.set("creator","http://github.com/helma/opentox-model")
		owl.set("title", URI.decode(data.dependentVariables.split(/#/).last) )
    #owl.set("title","#{URI.decode(activity_dataset.title)} lazar classification")
    owl.set("date",created_at.to_s)
    owl.set("algorithm",data.algorithm)
    owl.set("dependentVariables",activity_dataset.features.join(', '))
    owl.set("independentVariables",feature_dataset.features.join(', '))
		owl.set("predictedVariables", data.dependentVariables )
    #owl.set("predictedVariables",activity_dataset.features.join(', ') + "_lazar_classification")
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

	@prediction = OpenTox::Dataset.new 
	@prediction.creator = lazar.uri
	dependent_variable = YAML.load(lazar.yaml).dependentVariables
	@prediction.title = URI.decode(dependent_variable.split(/#/).last) 
	case dependent_variable
	when /classification/
		prediction_type = "classification"
	when /regression/
		prediction_type = "regression"
	end

	if compound_uri
    # look for cached prediction first
    if cached_prediction = Prediction.first(:model_uri => lazar.uri, :compound_uri => compound_uri)
      @prediction = YAML.load(cached_prediction.yaml)
    else
      begin
        # AM: switch here between regression and classification
        eval "lazar.#{prediction_type}(compound_uri,@prediction,true) unless lazar.database_activity?(compound_uri,@prediction)"
        Prediction.create(:model_uri => lazar.uri, :compound_uri => compound_uri, :yaml => @prediction.to_yaml)
      rescue
        LOGGER.error "#{prediction_type} failed for #{compound_uri} with #{$!} "
        halt 500, "Prediction of #{compound_uri} failed."
      end
    end
		case request.env['HTTP_ACCEPT']
		when /yaml/ 
			@prediction.to_yaml
		when 'application/rdf+xml'
			@prediction.to_owl
    else
      halt 400, "MIME type \"#{request.env['HTTP_ACCEPT']}\" not supported." 
		end

	elsif dataset_uri
    response['Content-Type'] = 'text/uri-list'
		task_uri = OpenTox::Task.as_task("Predict dataset",url_for("/#{lazar.id}", :full)) do
			input_dataset = OpenTox::Dataset.find(dataset_uri)
			input_dataset.compounds.each do |compound_uri|
				# AM: switch here between regression and classification
				begin
					eval "lazar.#{prediction_type}(compound_uri,@prediction) unless lazar.database_activity?(compound_uri,@prediction)"
				rescue
					LOGGER.error "#{prediction_type} failed for #{compound_uri} with #{$!} "
				end
			end
			begin
				uri = @prediction.save.chomp
			rescue
				halt 500, "Could not save prediction dataset"
			end
	  end
    halt 202,task_uri
	end

end
