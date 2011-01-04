require 'net/http'
require 'xmlsimple'
require 'sanitize'
require 'json'
require 'find'

task :default do
  
  to_infopath = ENV['infopath']
  
  Find.find(ENV["folder"]) do |path|
    
      if !FileTest.directory?(path) && path.include?("ok_httpUrl")
        file = path.slice(0,path.index('_')).gsub(ENV["folder"] + '/', '')
        output_folder = File.join('processed', file)
        output_folder = File.join('infopath', output_folder) if to_infopath
        
        if File.exists? output_folder
          FileUtils.rm_rf output_folder
        end
        puts "Processing #{output_folder}"
        FileUtils.mkdir_p output_folder
        
        data = XmlSimple.xml_in(path)
        
        if to_infopath
          data['document'].each{|doc|
            File.open(File.join(output_folder, "#{doc['id']}.xml"), 'w') { |f|
              document = create_document(doc)
              f.write(create_infopath(document))
            }
          }
        else  
          documents = Array.new
          data['document'].each{ |doc| 
            #File.open(File.join(output_folder, "#{doc['id']}.json"), 'w') { |f|
            #  f.write(JSON.pretty_generate(create_document(doc)))
            #}
            documents << create_document(doc)
          }
          File.open(File.join(output_folder, "all.json"), 'w') { |f|
            f.write(JSON.pretty_generate(documents))
          }
        end
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
    #document['description'] = doc['description'].to_s
    document['description'] = Sanitize.clean(doc['body'].to_s.strip_cdata, Sanitize::Config::RELAXED)
    
    document
end

def create_infopath (document)
  "<?mso-infoPathSolution name=\"urn:schemas-microsoft-com:office:infopath:ResourceForm:-myXSD-2010-08-09T08-39-43\" solutionVersion=\"1.0.0.68\" productVersion=\"14.0.0.0\" PIVersion=\"1.0.0.0\" href=\"http://localhost:8081/FormServerTemplates/ARMSResourceForm.xsn\"?>
  <?mso-application progid=\"InfoPath.Document\" versionProgid=\"InfoPath.Document.3\"?>
  <?mso-infoPath-file-attachment-present ?>
  <my:myFields xmlns:my=\"http://schemas.microsoft.com/office/infopath/2003/myXSD/2010-08-09T08:39:43\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:pc=\"http://schemas.microsoft.com/office/infopath/2007/PartnerControls\" xmlns:ma=\"http://schemas.microsoft.com/office/2009/metadata/properties/metaAttributes\" xmlns:d=\"http://schemas.microsoft.com/office/infopath/2009/WSSList/dataFields\" xmlns:q=\"http://schemas.microsoft.com/office/infopath/2009/WSSList/queryFields\" xmlns:dfs=\"http://schemas.microsoft.com/office/infopath/2003/dataFormSolution\" xmlns:dms=\"http://schemas.microsoft.com/office/2009/documentManagement/types\" xmlns:xd=\"http://schemas.microsoft.com/office/infopath/2003\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">
    <my:Title>#{document['title']}</my:Title>
    <my:URL>#{document['url']}</my:URL>
    <my:Publisher>#{document['publisher']}</my:Publisher>
    <my:AdditionalContributors />
    <my:GeographicalAreas />
    <my:PublicationType>#{document['publicationType']}</my:PublicationType>
    <my:Description>
      <html xmlns=\"http://www.w3.org/1999/xhtml\" xml:space=\"preserve\">
        #{document['description']}
       </html>
    </my:Description>
    <my:ResourceType>#{document['resourceType']}</my:ResourceType>
    <my:Attachment xsi:nil=\"true\" />
    <my:HasAttachment>false</my:HasAttachment>
    <my:Speciality>#{document['name']}</my:Speciality>
    <my:Keywords>#{document['topics']}</my:Keywords>
    <my:PublicationDate>#{document['publicationDate']}</my:PublicationDate>
  </my:myFields>"
end

class String
  def strip_cdata
    self.gsub('<![CDATA[','').gsub(']]>','')
  end
  def capitalize_each
    self.split(" ").each{|word| word.capitalize!}.join(" ")
  end
end