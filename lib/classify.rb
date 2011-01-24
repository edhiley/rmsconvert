def classify_url(url)
  content = "<?xml version=\"1.0\" ?>
  <request op=\"CLASSIFY\">
    <document>   
      <path>#{url}</path>
      <multiarticle />
      <language>en1</language>
      <clustering type=\"RMS\" threshold=\"48\" />
      <threshold>48</threshold>
      <min_average_article_pagesize>1.0</min_average_article_pagesize>
      <char_count_cutoff>500000</char_count_cutoff>
      <document_score_limit>0</document_score_limit>
    </document>
  </request>"

  # crawl url to memory...
  # upload with form...

  post_data = Curl::PostField.file("XML_INPUT", "classify.xml"){|field|
    field.content = content
  }  
  
  c = Curl::Easy.new("http://80.71.2.9:5058/index.html")
  c.multipart_form_post = true
  c.http_post(post_data)

  puts c.response_code, c.body_str

end