require 'net/http'
require 'xmlsimple'
require 'sanitize'
require 'json'
require 'find'
require 'csv'
require 'prettyprint'
require 'yaml'

require 'open-uri'
require 'uri'

require 'lib/specialities'
require 'lib/classify'

require 'curb'

## TODO
# need to try catorgorise the urls...
# output will look like:
# article url, mapped terms, autocat terms (relevancy...)

@mappings
@csv_paths
@specialism_mapping
@intended_audience = /Intended\saudience:<\/strong>\s*(.*?)<\/p>/
@mapping_data_folder = "mapping_data"
 
task :generate_csv_paths do
  
  @csv_paths = []
  
  Find.find(@mapping_data_folder) do |path|
    @csv_paths << path if !FileTest.directory?(path)
  end
  
  @csv_paths
end

task :find_ontology_ids => [:generate_csv_paths] do

  @known_paths = Hash.new
  
  @csv_paths.each{|path|
    @new_mappings = []
    
    
    CSV.foreach(path) do |row|
      
      # is not the head row and is not excluded from processing
      if row[0] != "SC_TERM" and row[3] != "1"
        
        term = row[1].to_s.strip

        if @known_paths[term].nil?
          url = "http://80.71.2.9/ses?TBDB=disp_taxonomy&TEMPLATE=service.json&SERVICE=term&TERM=#{URI.escape(term)}"
          puts "retrieving #{url} ..."

          begin
            f = open(url)
            raw_json = f.read
            data = JSON.parse(raw_json)
          rescue StandardError => boom
            p boom
            data = nil
          end
          
          if data.nil? or data["terms"].nil?
            @known_paths[term] = {
              :path => [],
              :ontology_id => 0
            }
            
            puts "no term mapping found for #{URI.escape(term)}"
          else
            raise "More than one term returned for #{term}, there should only be one" if data["terms"].count > 1
          
            @known_paths[term] = process_term(data)  
          end
    
          
        end

        term_info = @known_paths[term]

        @new_mappings << {
          "SC_TERM" => row[0],
          "MESH_TERM" => row[1],
          "MESH_ID" => row[2],
          "IGNORE" => 0, # excluding ignored rows already
          "ONTOLOGY_ID" => term_info[:ontology_id],
          "PATH" => term_info[:paths].to_json
        }
        
      end
    end
    
    CSV.open("#{@mapping_data_folder}/#{File.basename(path, ".csv")}_converted.csv", "wb") do |csv|
      @new_mappings.each{|m|
        csv << [m["SC_TERM"], m["MESH_TERM"], m["MESH_ID"], m["IGNORE"], m["ONTOLOGY_ID"], m["PATH"]]
      }
    end
  } 
  
end

task :generate_mappings => [:generate_csv_paths] do
  
  puts "generating mappings..."
  
  @mappings = Specialities.new

  @csv_paths.each{|path|
              
    specialism_name = path.split("/")[1].gsub(".csv","")
    
    specialism = @mappings.add(specialism_name)
    
    CSV.foreach(path) do |row|
      
      # is not the head row and is not exluded from processing
      if row[0] != "TOPIC" and row[3] != "1"
        term_path = JSON.parse(row[5]) if row[5] != "null"
        specialism.add(row[0], row[1], row[2], row[4], term_path)
      end
      
    end
    
    puts "processed #{specialism_name}, #{specialism.length} mapped topics"
    
  }
   
  File.open("mappings.yaml", "w") { |file| YAML.dump(@mappings, file) }
  puts "processed mappings written to mappings.yaml"
  
end

task :default => [:generate_mappings] do
  
  Find.find(ENV["folder"]) do |path|
    
      if !FileTest.directory?(path) && path.include?("ok_httpUrl")
        
        file = File.basename(path, ".xml")
        file = file.slice(0,file.index('_')).downcase
        
        output_folder = File.join('processed', file)
        
        @specialism_mapping = @mappings[file]
        
        
        FileUtils.rm_rf output_folder if File.exists? output_folder
                
        puts "Processing #{output_folder}"
        puts "#{@specialism_mapping.count} mappings found" unless @specialism_mapping.nil?
        puts "No mappings found for #{file}, please create a CSV file named #{file}.csv with SC_TERM,MESH_TERM,MESH_ID,IGNORE columns" if @specialism_mapping.nil?
        
        
        FileUtils.mkdir_p output_folder
        
        data = XmlSimple.xml_in(path)
     
        puts data['document'].count
     
        documents = Array.new
        data['document'].each{ |doc| 
          documents << create_document(doc, file)
        }
        File.open(File.join(output_folder, "all.json"), 'w') { |f|
          f.write(JSON.pretty_generate(documents))
        }
      
      end
   end

end

def create_document (doc, area_of_interest)
    document = Hash.new

    keywords = Sanitize.clean(doc['topics'].to_s.strip_cdata, Sanitize::Config::RELAXED)

    # legacy RMS fields
    document['RMSId'] = doc['id'].to_s
    document['RMSName'] = doc['name'].to_s.strip_cdata.strip
    document['RMSRootDirectory'] = doc['rootDirectory'].to_s.strip_cdata
    #document['RMSLastReviewDate'] = doc['lastReviewDate'].to_s.to_date
    document['RMSKeywords'] = keywords

    document['RelatedUrls'] = [] # seek origin
    document['TargetCountry'] = []
    
    document['Title'] = doc['title'].to_s
    document['Description'] = Sanitize.clean(doc['body'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    document['Url'] = doc['url'].to_s.strip_cdata
    document['Attachment'] = ""
    
    # these will now need mapping according to mapping_data/controlled_fields
    document['PublicationType'] = [doc['publicationType'].to_s.capitalize_each]
    
    
    # the source and publisher are now to be mapped - there will be a file for this...
    document['Source'] = [area_of_interest]
    document['Publisher'] = doc['publisher'].to_s
    
    
    audience = document['Description'].scan(@intended_audience)[0]
    document['Audience'] = audience[0].to_audiences rescue []
    
    
    
    document['PublicationDate'] = doc['publicationDate'].to_s.to_date
    document['ReviewDate'] = doc['expiryDate'].to_s.to_date
    
    document['ExpiryDate'] = doc['expiryDate'].to_s.to_date
    
    document['Tags'] = map_keywords(keywords.split(",")) unless @specialism_mapping.nil?
    document['AreaOfInterest'] = [area_of_interest]
    document['CreatedDate'] = Time.now.to_s.to_date
    
    document['Contributor'] = doc['creator'].to_s.split(", ")
        
    document
end

def map_keywords(keywords)
  tags = []

  keywords.each{|k|
    map = @specialism_mapping[k]
    
    if !map.nil? 
      tags << map.each.collect { |m|
        {
          "Id" => m.term_id,
          "MeshId" => m.mesh_id,
          "Name" => m.term,
          "Path" => m.path,
          "Score" => 0.9
        }
      }
    end
  }
  
  tags.flatten!
  # find matching paths, need to add lookup to real terms in ontology (using service)?
end

def process_term(data)
  
  term_data = data["terms"][0]["term"]

  term_paths = term_data["paths"]
  
  mapped_paths = []
  
  term_paths.each{|paths|
    mapped_paths << "|" + paths["path"].collect{|path| path["field"]["name"] }.join('|') + "|"
  }
  
  term_info = {
    :paths => mapped_paths,
    :ontology_id => term_data["id"]
  }
end

class String
  def to_audiences
    self.gsub(/\.|\302|\240/, "").split(/,/).collect { |a|  
      a.strip.capitalize_each  }
  end
  
  def to_date
    Date.parse(self).strftime('%Y-%m-%dT%H:%M:%S%z') rescue nil #"that's a no-no #{self}"
  end
  
  def to_sort
    self.gsub(/[^a-z0-9]+/i, '').downcase
  end
  def strip_cdata
    self.gsub('<![CDATA[','').gsub(']]>','')
  end
  def capitalize_each
    self.split(" ").each{|word| word.capitalize!}.join(" ")
  end
end