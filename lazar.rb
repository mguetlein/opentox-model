require 'redland'
require 'rdf/redland'
require 'rdf/redland/util'

@@storage = Redland::MemoryStore.new
@@parser = Redland::Parser.new
@@serializer = Redland::Serializer.new

get '/?' do # get index of models
	Dir["models/*"].collect{|model|  url_for("/", :full) + File.basename(model,".yaml")}.sort.join("\n")
end

get '/:id/?' do
	path = File.join("models",params[:id] + ".yaml")
	if File.exists? path
		send_file path
	else
		status 404
		"Model #{params[:id]} does not exist."
	end
end

delete '/:id/?' do
	path = File.join("models",params[:id] + ".yaml")
	if File.exists? path
		File.delete path
		"Model #{params[:id]} deleted."
	else
		status 404
		"Model #{params[:id]} does not exist."
	end
end

post '/lazar/?' do # create model
	halt 404, "Dataset #{params[:activity_dataset_uri]} not found" unless  OpenTox::Dataset.find(params[:activity_dataset_uri])
	halt 404, "Dataset #{params[:feature_dataset_uri]} not found" unless OpenTox::Dataset.find(params[:feature_dataset_uri])
	activities = Redland::Model.new @storage
	features = Redland::Model.new @storage
	training_activities = OpenTox::Dataset.find params[:activity_dataset_uri]
	training_features = OpenTox::Dataset.find params[:feature_dataset_uri]
	@@parser.parse_string_into_model(activities,training_activities,'/')
	@@parser.parse_string_into_model(features,training_features,'/')
	feature = Redland::Node.new(Redland::Uri.new(File.join(@@config[:services]["opentox-algorithm"],'fminer')))
	p_value = Redland::Node.new(Redland::Uri.new(File.join(@@config[:services]["opentox-algorithm"],'fminer/p_value')))
	effect = Redland::Node.new(Redland::Uri.new(File.join(@@config[:services]["opentox-algorithm"],'fminer/effect')))

	smarts = []
	p_vals = {}
	effects = {}
	fingerprints = {}
	features.triples do |s,p,o|
		s = s.uri.to_s.sub(/^\//,'') 
		case p
		when feature
			fingerprints[s] = [] unless fingerprints[s]
			fingerprints[s] << o.uri.to_s.sub(/^\//,'') 
		when p_value
			sma = s.to_s
			smarts << sma
			p_vals[sma] = o.to_s.to_f
		when effect
			sma = s.to_s
			effects[sma] = o.to_s
		end
	end

	activity_uris = []
	act = {}
	activities.triples do |s,p,o|
		activity_uris << p.uri.to_s
		s = s.uri.to_s
		case o.to_s
		when "true"
			act[s] = true
		when "false"
			act[s] = false
		end
	end

	activity_uris.uniq!
	if activity_uris.size != 1
		halt 400
		"Dataset #{params[:activity_dataset_uri]} has not exactly one feature."
	end

	id = Dir["models/*"].collect{|models|  File.basename(models,".yaml").to_i}.sort.last
	if id.nil?
		id = 1
	else
		id += 1
	end

	File.open(File.join("models",id.to_s + ".yaml"),"w") do |f|
		f.write({
			:endpoint => activity_uris[0],
			:features => smarts,
			:p_values => p_vals,
			:effects => effects,
			:fingerprints => fingerprints,
			:activities => act
		}.to_yaml)
	end
	url_for("/#{id}", :full)

end

# PREDICTIONS
post '/:id/?' do # create prediction
	path = File.join("models",params[:id] + ".yaml")
	if !File.exists? path
		status 404
		"Model #{params[:id]} does not exist."
	end

	compound = OpenTox::Compound.new :uri => params[:compound_uri]

	data = YAML.load_file path

	# find database activities
	if data[:activities][compound.uri]
		output = Redland::Model.new @storage
		output.add Redland::Uri.new(compound.uri), Redland::Uri.new(data[:endpoint]), Redland::Literal.new(data[:activities][compound.uri].to_s)
		halt 200, @@serializer.model_to_string(Redland::Uri.new(url_for("/",:full)), output)
	end

	compound_matches = compound.match data[:features]

	conf = 0.0
	neighbors = []
	classification = nil

	data[:fingerprints].each do |uri,matches|
		sim = weighted_tanimoto(compound_matches,matches,data[:p_values])
		if sim > 0.3

			neighbors << uri
			case data[:activities][uri].to_s
			when 'true'
				conf += OpenTox::Utils.gauss(sim) 
			when 'false'
				conf -= OpenTox::Utils.gauss(sim)
			end
		end
		conf = conf/neighbors.size
		if conf > 0.0
			classification = true
		elsif conf < 0.0
			classification = false
		end
	end

	output = Redland::Model.new @storage

	output.add Redland::Uri.new(compound.uri), Redland::Uri.new(url_for("/#{params[:id]}/classification",:full)), classification.to_s
	output.add Redland::Uri.new(compound.uri), Redland::Uri.new(url_for("/#{params[:id]}/confidence",:full)), conf.to_s
	@@serializer.model_to_string(Redland::Uri.new(url_for("/",:full)), output)
	
#	{ :classification => classification,
#		:confidence => conf,
#		:neighbors => neighbors,
#		:features => compound_matches
#	}.to_yaml
end


def weighted_tanimoto(fp_a,fp_b,p)
	common_features = fp_a & fp_b
	all_features = fp_a + fp_b
	common_p_sum = 0.0
	if common_features.size > 0
		common_features.each{|f| common_p_sum += p[f]}
		all_p_sum = 0.0
		all_features.each{|f| all_p_sum += p[f]}
		common_p_sum/all_p_sum
	else
		0.0
	end
end
