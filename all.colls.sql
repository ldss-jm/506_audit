select 'b' || colls.record_num || 'a' as bnum, colls.field_content as collection, vt.field_content as "506"
from 
(select v.record_num, v.record_id, v.field_content
from sierra_view.varfield_view v
where v.marc_tag = '773'
and v.field_content like '%(online collection)%'
) colls
LEFT OUTER JOIN sierra_view.varfield vt on vt.marc_tag = '506' and vt.record_id = colls.record_id
