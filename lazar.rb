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

post '/?' do # create model

	case request.content_type
	when /application\/x-yaml|text\/yaml/
		input =	request.env["rack.input"].read
		id = Dir["models/*"].collect{|model|  File.basename(model,".yaml").to_i}.sort.last
		if id.nil?
			id = 1
		else
			id += 1
		end
		File.open(File.join("models",id.to_s + ".yaml"),"w+") { |f| f.write input }
		url_for("/#{id}", :full)
	else
		halt 400, "MIME type \"#{request.content_type}\" not supported."
	end

	url_for("/#{id}", :full)

end

# PREDICTIONS
post '/:id/?' do # create prediction

  storage = Redland::MemoryStore.new
  parser = Redland::Parser.new
  serializer = Redland::Serializer.new

	path = File.join("models",params[:id] + ".yaml")
	if !File.exists? path
		status 404
		"Model #{params[:id]} does not exist."
	end

	compound = OpenTox::Compound.new :uri => params[:compound_uri]

	data = YAML.load_file path

	# find database activities
	if data[:activities][compound.uri]
		output = Redland::Model.new storage
		output.add Redland::Uri.new(compound.uri), Redland::Uri.new(data[:endpoint]), Redland::Literal.new(data[:activities][compound.uri].to_s)
		response = serializer.model_to_string(Redland::Uri.new(url_for("/",:full)), output)
	else
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
					puts "t: #{sim}"
					conf += OpenTox::Utils.gauss(sim)
				when 'false'
					conf -= OpenTox::Utils.gauss(sim)
				end
			end
		end

		conf = conf/neighbors.size
		if conf > 0.0
			classification = true
		elsif conf < 0.0
			classification = false
		end

		output = Redland::Model.new storage
		output.add Redland::Uri.new(compound.uri), Redland::Uri.new(url_for("/#{params[:id]}/classification",:full)), classification.to_s
		output.add Redland::Uri.new(compound.uri), Redland::Uri.new(url_for("/#{params[:id]}/confidence",:full)), conf.to_s
		neighbors.each do |neighbor|
			output.add Redland::Uri.new(compound.uri), Redland::Uri.new(url_for("/#{params[:id]}/neighbor",:full)), Redland::Uri.new(neighbor)
		end
		response =serializer.model_to_string(Redland::Uri.new(url_for("/",:full)), output)
	end
	
	m = { :classification => classification,
		:confidence => conf,
		:neighbors => neighbors,
		:features => compound_matches
	}
	puts m.to_yaml

	response
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
