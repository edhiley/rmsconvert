require 'net/http'
require 'xmlsimple'
require 'sanitize'
require 'json'
require 'find'
require 'csv'
require 'prettyprint'
require 'yaml'

require 'lib/specialities'

@mappings
@specialism_mapping
@topics
@paths

task :generate_mappings do
  
  puts "generating mappings..."
  
  @mappings = Specialities.new

  mapping_data = "mapping_data"
  
  Find.find(mapping_data) do |path|
        
    if !FileTest.directory?(path)
      
      specialism_name = path.split("/")[1].gsub(".csv","")
      
      specialism = @mappings.add(specialism_name)
      
      CSV.foreach(path) do |row|
        
        # is not the head row and is not exluded from processing
        if row[0] != "TOPIC" and row[3] != "1"
          specialism.add(row[0], row[1], row[2])
        end
        
      end
      
      puts "processed #{specialism_name}, #{@mappings.length} mapped topics"
      
    end
    
  end
   
  File.open("mappings.yaml", "w") { |file| YAML.dump(@mappings, file) }
  puts "processed mappings written to mappings.yaml"
  
end

task :default => [:generate_mappings] do
  
  Find.find(ENV["folder"]) do |path|
    
      if !FileTest.directory?(path) && path.include?("ok_httpUrl")
        file = path.slice(0,path.index('_')).gsub(ENV["folder"] + '/', '').downcase
        output_folder = File.join('processed', file)
        
        @specialism_mapping = @mappings[file]
        
        FileUtils.rm_rf output_folder if File.exists? output_folder
        
        puts "Processing #{output_folder}"
        puts "#{@specialism_mapping.count} mappings found"
        FileUtils.mkdir_p output_folder
        
        data = XmlSimple.xml_in(path)
     
        documents = Array.new
        data['document'].each{ |doc| 
          documents << create_document(doc)
        }
        File.open(File.join(output_folder, "all.json"), 'w') { |f|
          f.write(JSON.pretty_generate(documents))
        }
      
      end
   end

end

def create_document (doc)
    document = Hash.new
    document['id'] = doc['id'].to_s
    document['name'] = doc['name'].to_s.strip_cdata.strip
    document['rootDirectory'] = doc['rootDirectory'].to_s.strip_cdata
    document['url'] = doc['url'].to_s.strip_cdata
    document['title'] = doc['title'].to_s
    document['publicationDate'] = doc['publicationDate'].to_s
    document['publisher'] = doc['publisher'].to_s
    document['publicationType'] = doc['publicationType'].to_s.capitalize_each
    document['topics'] = doc['topics'].to_s.strip_cdata.strip
    document['resourceType'] = doc['resourceType'].to_s
    document['description'] = Sanitize.clean(doc['body'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    
    keywords = Sanitize.clean(doc['topics'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    
    map_keywords keywords.split(",")
    
    document['topics'] = @topics
    document['paths'] = @paths
    
    document
end

def map_keywords(keywords)
  @topics = []
  @paths = []
  
  keywords.each{|k|
    map = @specialism_mapping[k]
    
    if !map.nil? 
      @topics << map.each.collect{ |m| m.term }
      @paths << map.each.collect{ |m| m.mesh_id }
    end
  }
  
  @topics.flatten!
  @paths.flatten!
   
  # find matching paths, need to add lookup to real terms in ontology (using service)?

end

class String
  def strip_cdata
    self.gsub('<![CDATA[','').gsub(']]>','')
  end
  def capitalize_each
    self.split(" ").each{|word| word.capitalize!}.join(" ")
  end
end