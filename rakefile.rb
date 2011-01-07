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

# option to deserialize mappings from yaml... ?

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
      
      puts "processed #{specialism_name}, #{specialism.length} mapped topics"
      
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

    # legacy RMS fields
    document['RMSId'] = doc['id'].to_s
    document['RMSName'] = doc['name'].to_s.strip_cdata.strip
    document['RMSRootDirectory'] = doc['rootDirectory'].to_s.strip_cdata

    document['RelatedUrls'] = [] # seek origin
    document['TargetCountry'] = ""
    document['Creator'] = "RMS Import"
    document['ResourceType'] = doc['resourceType'].to_s
    document['Title'] = doc['title'].to_s
    document['TitleForSorting'] = document['Title'].to_sort
    document['Description'] = Sanitize.clean(doc['body'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    document['Url'] = doc['url'].to_s.strip_cdata
    document['Attachment'] = ""
    document['PublicationType'] = doc['publicationType'].to_s.capitalize_each
    document['Audience'] = ""  # seek origin, question on Evidence Updates
    document['PublicationDate'] = doc['publicationDate'].to_s.to_date
    document['ReviewDate']  # seek origin
    document['Source']  # seek origin
    document['Publisher'] = doc['publisher'].to_s
    document['Contributor'] = "RMS Import"
    document['ExpiryDate'] # seek origin
    
    keywords = Sanitize.clean(doc['topics'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    document['Tags'] = map_keywords(keywords.split(","))
    document['AreaOfInterest'] = area_of_interest
    document['CreatedDate'] = Time.now.to_s
    
    # dates = /Date([number])/ - unable to process to this, (to_i) needs (1.9.x)
    
    document
end

def map_keywords(keywords)
  tags = []

  keywords.each{|k|
    map = @specialism_mapping[k]
    
    if !map.nil? 
      tags << map.each.collect { |m|
        {
          "Id" => nil,
          "MeshId" => m.mesh_id,
          "Name" => m.term,
          "Path" => nil,
          "Score" => 1.0
        }
      }
    end
  }
  
  tags.flatten!
  # find matching paths, need to add lookup to real terms in ontology (using service)?
end

class String
  def to_date
    Date.parse(self) rescue nil
  end
  
  def to_sort
    self.gsub(/[^a-z0-9]+/i, '').downcase
    #self.gsub(/[^\x20-\x7E]/, '').downcase
  end
  def strip_cdata
    self.gsub('<![CDATA[','').gsub(']]>','')
  end
  def capitalize_each
    self.split(" ").each{|word| word.capitalize!}.join(" ")
  end
end