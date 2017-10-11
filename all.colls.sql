with recs as (select distinct on (v.record_id)
              * from sierra_view.varfield v
              inner join sierra_view.record_metadata rm on rm.id = v.record_id
              where v.marc_tag = '773'
               and v.field_content like '%(online collection)%')

select 'b' || recs.record_num || 'a' as bnum
     , (SELECT STRING_AGG(Trim(trailing FROM vs.field_content), ';;;')
        FROM   sierra_view.varfield vs
        where vs.marc_tag = '773'
        and vs.field_content like '%(online collection)%'
        and vs.record_id = recs.record_id) as _773s
     , (SELECT STRING_AGG(Trim(trailing FROM v506.field_content), ';;;')
        FROM   sierra_view.varfield v506
        where v506.marc_tag = '506'
        and v506.record_id = recs.record_id) as _506s
from recs