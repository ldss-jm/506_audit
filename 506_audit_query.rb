load '../postgres_connect/connect.rb'

c = Connect.new
puts "running query"
c.make_query('all.colls.sql')
c.write_results('output_SQL_results.txt',
              include_headers: true,
              format: 'tsv'
)